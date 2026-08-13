import BoardProtocol
import Foundation
import Network

enum BoardConnectionChannelEvent: Sendable {
    case ready
    case data(Data)
    case closed(String?)
}

protocol BoardConnectionChannel: AnyObject, Sendable {
    func start(
        queue: DispatchQueue,
        eventHandler: @escaping @Sendable (BoardConnectionChannelEvent) -> Void
    )
    func send(_ data: Data)
    func cancel()
}

final class NetworkBoardConnectionChannel: BoardConnectionChannel, @unchecked Sendable {
    private static let maximumTLSWriteBytes = 8_000
    private let connection: NWConnection
    private var eventHandler: (@Sendable (BoardConnectionChannelEvent) -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(
        queue: DispatchQueue,
        eventHandler: @escaping @Sendable (BoardConnectionChannelEvent) -> Void
    ) {
        self.eventHandler = eventHandler
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                eventHandler(.ready)
                self.receive()
            case let .failed(error):
                eventHandler(.closed(error.localizedDescription))
            case .cancelled:
                eventHandler(.closed(nil))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ data: Data) {
        send(data, offset: 0)
    }

    private func send(_ data: Data, offset: Int) {
        guard offset < data.count else { return }
        let end = min(data.count, offset + Self.maximumTLSWriteBytes)
        connection.send(
            content: data.subdata(in: offset..<end),
            completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil {
                    self.connection.cancel()
                } else {
                    self.send(data, offset: end)
                }
            }
        )
    }

    func cancel() {
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: boardProtocolMaximumFrameBytes + 4) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.eventHandler?(.data(data))
            }
            if complete || error != nil {
                self.connection.cancel()
            } else {
                self.receive()
            }
        }
    }
}
