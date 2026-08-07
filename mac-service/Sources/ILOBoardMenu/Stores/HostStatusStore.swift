import AppKit
import BoardHostCore
import Foundation

@MainActor
final class HostStatusStore: ObservableObject {
    @Published private(set) var state: HostServiceState = .starting
    @Published private(set) var boardID = "—"
    @Published private(set) var servicePort: UInt16?
    @Published private(set) var lastSync: Date?

    private var server: BoardServer?

    init() {
        start()
    }

    func start() {
        guard server == nil else { return }
        state = .starting
        do {
            let configuration = try HostConfiguration.load()
            let secret = try KeychainPSKStore().load(boardID: configuration.boardID)
            boardID = configuration.boardID
            servicePort = configuration.port
            let server = BoardServer(
                boardID: configuration.boardID,
                secret: secret,
                source: MockTaskSource()
            ) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            self.server = server
            try server.start(port: configuration.port)
        } catch HostConfigurationError.notProvisioned {
            state = .notProvisioned
        } catch {
            state = .failed(error.localizedDescription)
            server = nil
        }
    }

    func stop() {
        server?.stop()
        server = nil
        state = .stopped
    }

    func copyBoardID() {
        guard boardID != "—" else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(boardID, forType: .string)
    }

    private func handle(_ event: BoardServerEvent) {
        switch event {
        case let .listenerReady(port):
            servicePort = port
            state = .listening
        case let .listenerFailed(message):
            state = .failed(message)
            server = nil
        case .boardConnected:
            state = .connected
        case .boardDisconnected:
            if server != nil { state = .listening }
        case let .snapshotSent(date):
            lastSync = date
            state = .connected
        }
    }
}
