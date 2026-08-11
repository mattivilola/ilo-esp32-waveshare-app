import AppKit
import BoardHostCore
import BoardProtocol
import Foundation
import ILOBoardMenuSupport

@MainActor
final class HostStatusStore: ObservableObject {
    @Published private(set) var state: HostServiceState = .starting
    @Published private(set) var boardID = "—"
    @Published private(set) var servicePort: UInt16?
    @Published private(set) var lastSync: Date?
    @Published private(set) var connectionHistory: [ConnectionHistoryEntry]
    @Published private(set) var macPowerStatus: MacPowerStatus?
    @Published private(set) var xNewsStatus: XNewsFeatureStatus
    @Published private(set) var xNewsNotice: String?
    @Published private(set) var pairingAuthorizationNotice: String?

    private var server: BoardServer?
    private var historyLog: ConnectionHistoryLog
    private let defaults: UserDefaults
    private let powerStatusSource: any MacPowerStatusProviding
    private let xNewsFeatureController: XNewsFeatureController
    private let usesCompanionCredential: Bool
    private var powerMonitorTask: Task<Void, Never>?
    private static let historyDefaultsKey = "ilo-board.connection-history.v1"

    init(
        defaults: UserDefaults = .standard,
        powerStatusSource: any MacPowerStatusProviding = CachedMacPowerStatusSource(),
        xNewsFeatureController: XNewsFeatureController = XNewsFeatureController(),
        usesCompanionCredential: Bool = KeychainPSKStore.shouldUseCompanionCredential
    ) {
        self.defaults = defaults
        self.powerStatusSource = powerStatusSource
        self.xNewsFeatureController = xNewsFeatureController
        self.usesCompanionCredential = usesCompanionCredential
        historyLog = ConnectionHistoryLog.decode(defaults.data(forKey: Self.historyDefaultsKey))
        connectionHistory = historyLog.entries
        macPowerStatus = nil
        xNewsStatus = xNewsFeatureController.status()
        xNewsNotice = nil
        pairingAuthorizationNotice = nil
        start()
        powerMonitorTask = Task { [weak self, powerStatusSource] in
            while !Task.isCancelled {
                let status = await powerStatusSource.currentStatus()
                guard let self else { return }
                self.macPowerStatus = status
                self.refreshXNewsStatus()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func start() {
        guard server == nil else { return }
        pairingAuthorizationNotice = nil
        do {
            let configuration = try HostConfiguration.load()
            boardID = configuration.boardID
            servicePort = configuration.port
            let secret: Data
            if usesCompanionCredential {
                do {
                    secret = try KeychainPSKStore().loadForCompanion(boardID: configuration.boardID)
                } catch PairingError.notFound {
                    state = .pairingAuthorizationRequired
                    return
                }
            } else {
                secret = try KeychainPSKStore().load(boardID: configuration.boardID)
            }
            try startServer(configuration: configuration, secret: secret)
        } catch HostConfigurationError.notProvisioned {
            transition(to: .notProvisioned, recording: .setupRequired)
        } catch {
            transition(to: .failed(error.localizedDescription), recording: .serviceIssue)
            server = nil
        }
    }

    func authorizeSecurePairing() {
        guard server == nil, usesCompanionCredential else { return }
        pairingAuthorizationNotice = nil
        let configuration: HostConfiguration
        let secret: Data
        do {
            configuration = try HostConfiguration.load()
            boardID = configuration.boardID
            servicePort = configuration.port
            secret = try KeychainPSKStore().authorizeCompanion(boardID: configuration.boardID)
        } catch HostConfigurationError.notProvisioned {
            transition(to: .notProvisioned, recording: .setupRequired)
            return
        } catch PairingError.keychain(errSecAuthFailed),
                PairingError.keychain(errSecUserCanceled) {
            state = .pairingAuthorizationRequired
            pairingAuthorizationNotice = "Keychain access wasn’t granted. Nothing changed; you can try again when ready."
            return
        } catch {
            state = .pairingAuthorizationRequired
            pairingAuthorizationNotice = "Secure pairing couldn’t be authorized: \(error.localizedDescription)"
            return
        }

        do {
            try startServer(configuration: configuration, secret: secret)
        } catch {
            transition(to: .failed(error.localizedDescription), recording: .serviceIssue)
        }
    }

    deinit {
        powerMonitorTask?.cancel()
    }

    func stop() {
        server?.stop()
        server = nil
        transition(to: .stopped, recording: .serviceStopped)
    }

    func copyBoardID() {
        guard boardID != "—" else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(boardID, forType: .string)
    }

    func refreshXNewsStatus() {
        xNewsStatus = xNewsFeatureController.status()
    }

    func enableXNews(cadence: XNewsRefreshCadence = .daily) {
        do {
            try xNewsFeatureController.enable(cadence: cadence, explicitlyAllowsGrokTools: true)
            xNewsNotice = cadence == .daily
                ? "X News enabled daily; the board screen will appear on its next sync."
                : "X News enabled twice daily; the board screen will appear on its next sync."
        } catch GrokXNewsError.executableNotFound {
            xNewsNotice = "Grok CLI is not installed or executable. X News remains hidden."
        } catch {
            xNewsNotice = "Couldn’t enable X News. Its previous setting was preserved."
        }
        refreshXNewsStatus()
    }

    func disableXNews() {
        do {
            try xNewsFeatureController.disable()
            xNewsNotice = "X News disabled; its board screen will hide on the next sync."
        } catch {
            xNewsNotice = "Couldn’t disable X News. Its previous setting was preserved."
        }
        refreshXNewsStatus()
    }

    func diagnosticSummary(launchAtLogin: LaunchAtLoginState) -> String {
        let releaseInfo = AppReleaseInfo(infoDictionary: Bundle.main.infoDictionary)
        let snapshot = DiagnosticSnapshot(
            appVersion: releaseInfo.displayVersion,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            serviceState: state.diagnosticTitle,
            launchAtLoginState: launchAtLogin,
            lastSync: lastSync,
            activity: connectionHistory
        )
        return DiagnosticSummary.render(snapshot)
    }

    private func handle(_ event: BoardServerEvent) {
        switch event {
        case let .listenerReady(port):
            servicePort = port
            transition(to: .listening, recording: .waitingForBoard)
        case let .listenerFailed(message):
            transition(to: .failed(message), recording: .serviceIssue)
            server = nil
        case .boardConnected:
            transition(to: .connected, recording: .boardConnected)
        case .boardDisconnected:
            if server != nil {
                transition(to: .listening, recording: .boardDisconnected)
            }
        case let .snapshotSent(date):
            lastSync = date
            state = .connected
        }
    }

    private func startServer(configuration: HostConfiguration, secret: Data) throws {
        transition(to: .starting, recording: .serviceStarting)
        let server = BoardServer(
            boardID: configuration.boardID,
            secret: secret,
            source: CodexHistoryTaskSource(),
            powerStatusSource: powerStatusSource,
            eventHandler: { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
        )
        self.server = server
        do {
            try server.start(port: configuration.port)
        } catch {
            self.server = nil
            throw error
        }
    }

    private func transition(to newState: HostServiceState, recording activity: ConnectionHistoryEntry.Kind) {
        state = newState
        historyLog.record(activity)
        connectionHistory = historyLog.entries
        if let data = try? historyLog.encoded() {
            defaults.set(data, forKey: Self.historyDefaultsKey)
        }
    }
}
