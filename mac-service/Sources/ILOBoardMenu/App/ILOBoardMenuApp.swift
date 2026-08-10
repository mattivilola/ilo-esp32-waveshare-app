import AppKit
import BoardHostCore
import ILOBoardMenuSupport
import SwiftUI

final class ILOBoardAppDelegate: NSObject, NSApplicationDelegate {
    private var xNewsScheduleTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = BrandImage.image
        xNewsScheduleTask = Task {
            await XNewsRefreshCoordinator.shared.run()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        xNewsScheduleTask?.cancel()
    }
}

@main
struct ILOBoardMenuApp: App {
    @NSApplicationDelegateAdaptor(ILOBoardAppDelegate.self) private var appDelegate
    @StateObject private var store = HostStatusStore()
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @StateObject private var updater: SparkleUpdaterController

    init() {
        let processInfo = ProcessInfo.processInfo
        _updater = StateObject(wrappedValue: SparkleUpdaterController(
            automaticallyCheckAtLaunch: SparkleLaunchPolicy.allowsBackgroundChecks(
                environment: processInfo.environment,
                arguments: processInfo.arguments
            )
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuDashboardView(store: store, launchAtLogin: launchAtLogin, updater: updater)
        } label: {
            Label("ILO Board", systemImage: store.state.symbolName)
        }
        .menuBarExtraStyle(.window)
    }
}
