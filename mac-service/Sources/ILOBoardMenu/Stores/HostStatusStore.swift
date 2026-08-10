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

    private var server: BoardServer?
    private var historyLog: ConnectionHistoryLog
    private let defaults: UserDefaults
    private let powerStatusSource: any MacPowerStatusProviding
    private var powerMonitorTask: Task<Void, Never>?
    private static let historyDefaultsKey = "ilo-board.connection-history.v1"

    init(
        defaults: UserDefaults = .standard,
        powerStatusSource: any MacPowerStatusProviding = CachedMacPowerStatusSource()
    ) {
        self.defaults = defaults
        self.powerStatusSource = powerStatusSource
        historyLog = ConnectionHistoryLog.decode(defaults.data(forKey: Self.historyDefaultsKey))
        connectionHistory = historyLog.entries
        macPowerStatus = nil
        start()
        powerMonitorTask = Task { [weak self, powerStatusSource] in
            while !Task.isCancelled {
                let status = await powerStatusSource.currentStatus()
                guard let self else { return }
                self.macPowerStatus = status
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func start() {
        guard server == nil else { return }
        transition(to: .starting, recording: .serviceStarting)
        do {
            let configuration = try HostConfiguration.load()
            let secret = try KeychainPSKStore().load(boardID: configuration.boardID)
            boardID = configuration.boardID
            servicePort = configuration.port
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
            try server.start(port: configuration.port)
        } catch HostConfigurationError.notProvisioned {
            transition(to: .notProvisioned, recording: .setupRequired)
        } catch {
            transition(to: .failed(error.localizedDescription), recording: .serviceIssue)
            server = nil
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

    private func transition(to newState: HostServiceState, recording activity: ConnectionHistoryEntry.Kind) {
        state = newState
        historyLog.record(activity)
        connectionHistory = historyLog.entries
        if let data = try? historyLog.encoded() {
            defaults.set(data, forKey: Self.historyDefaultsKey)
        }
    }
}
