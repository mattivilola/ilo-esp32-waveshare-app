import AppKit
import BoardHostCore
import ILOBoardMenuSupport
import SwiftUI

private struct CompanionCaptureRequest {
    let outputURL: URL
    let timeoutSeconds: Int
    let force: Bool

    static func parse(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard let commandIndex = arguments.firstIndex(of: "--capture-board-screen"),
              arguments.indices.contains(commandIndex + 1)
        else { return nil }
        let output = NSString(string: arguments[commandIndex + 1]).expandingTildeInPath
        let timeout = arguments.firstIndex(of: "--capture-timeout").flatMap { index in
            arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
        } ?? 45
        return Self(
            outputURL: URL(fileURLWithPath: output).standardizedFileURL,
            timeoutSeconds: min(max(timeout, 1), 120),
            force: arguments.contains("--capture-force")
        )
    }
}

final class ILOBoardAppDelegate: NSObject, NSApplicationDelegate {
    private var xNewsScheduleTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = BrandImage.image
        if let capture = CompanionCaptureRequest.parse() {
            Task { await runCapture(capture) }
            return
        }
        FocusCompletionNotifier.prepare()
        xNewsScheduleTask = Task {
            await XNewsRefreshCoordinator.shared.run()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        xNewsScheduleTask?.cancel()
    }

    private func runCapture(_ request: CompanionCaptureRequest) async {
        do {
            if !request.force && FileManager.default.fileExists(atPath: request.outputURL.path) {
                throw CocoaError(.fileWriteFileExists)
            }
            guard FileManager.default.fileExists(
                atPath: request.outputURL.deletingLastPathComponent().path
            ) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let configuration = try HostConfiguration.load()
            let secret = try KeychainPSKStore().loadForCompanion(boardID: configuration.boardID)
            let capture = try await AuthenticatedScreenCapture.capture(
                configuration: configuration,
                secret: secret,
                timeoutSeconds: request.timeoutSeconds
            )
            let png = try ScreenCapturePNGEncoder.encode(capture)
            try png.write(to: request.outputURL, options: request.force ? .atomic : .withoutOverwriting)
            print("Saved authenticated 1024x600 board capture: \(request.outputURL.path)")
            Foundation.exit(EXIT_SUCCESS)
        } catch {
            fputs("ILO Board capture failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }
}

@main
struct ILOBoardMenuApp: App {
    @NSApplicationDelegateAdaptor(ILOBoardAppDelegate.self) private var appDelegate
    @StateObject private var store: HostStatusStore
    @StateObject private var weatherLocation: MacWeatherLocationController
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @StateObject private var updater: SparkleUpdaterController

    init() {
        let processInfo = ProcessInfo.processInfo
        let captureMode = CompanionCaptureRequest.parse(processInfo.arguments) != nil
        let weatherLocation = MacWeatherLocationController(autoRefresh: !captureMode)
        _weatherLocation = StateObject(wrappedValue: weatherLocation)
        _store = StateObject(wrappedValue: HostStatusStore(
            weatherLocationSource: weatherLocation.cache,
            autoStart: !captureMode
        ))
        _updater = StateObject(wrappedValue: SparkleUpdaterController(
            automaticallyCheckAtLaunch: SparkleLaunchPolicy.allowsBackgroundChecks(
                environment: processInfo.environment,
                arguments: processInfo.arguments
            )
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuDashboardView(
                store: store,
                weatherLocation: weatherLocation,
                launchAtLogin: launchAtLogin,
                updater: updater
            )
        } label: {
            Label("ILO Board", systemImage: store.state.symbolName)
        }
        .menuBarExtraStyle(.window)
    }
}
