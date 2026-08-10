import AppKit
import Foundation
import Sparkle

enum SparkleLaunchPolicy {
    static func allowsBackgroundChecks(environment: [String: String], arguments: [String]) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
            && !arguments.contains(where: { $0.hasPrefix("--uitest-") })
    }
}

@MainActor
final class SparkleUpdaterController: ObservableObject {
    @Published private(set) var isAvailable = false

    private let updaterController: SPUStandardUpdaterController?
    private let unavailableReason: String
    private var hasPerformedLaunchCheck = false

    init(
        bundle: Bundle = .main,
        automaticallyCheckAtLaunch: Bool = true
    ) {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

        guard let feedURL, !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updaterController = nil
            unavailableReason = "This development build has no update feed."
            return
        }
        guard let publicKey, !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updaterController = nil
            unavailableReason = "This build is missing its Sparkle public signing key."
            return
        }
        guard Self.supportsUpdates(at: bundle.bundleURL) else {
            updaterController = nil
            unavailableReason = "Move ILO Board to Applications before checking for updates."
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        unavailableReason = ""
        isAvailable = true

        if automaticallyCheckAtLaunch {
            performLaunchCheckIfEnabled()
        }
    }

    func checkForUpdates() {
        guard let updaterController else {
            presentUnavailableAlert()
            return
        }
        updaterController.checkForUpdates(nil)
    }

    func performLaunchCheckIfEnabled() {
        guard !hasPerformedLaunchCheck,
              let updaterController,
              updaterController.updater.automaticallyChecksForUpdates
        else {
            return
        }
        hasPerformedLaunchCheck = true
        updaterController.updater.checkForUpdatesInBackground()
    }

    private func presentUnavailableAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Updates are unavailable"
        alert.informativeText = unavailableReason
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func supportsUpdates(at bundleURL: URL) -> Bool {
        if bundleURL.path.hasPrefix("/Volumes/") || bundleURL.path.contains("/AppTranslocation/") {
            return false
        }
        return (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) != true
    }
}
