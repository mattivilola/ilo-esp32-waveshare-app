import Foundation

public struct ConnectionHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case serviceStarting
        case waitingForBoard
        case boardConnected
        case boardDisconnected
        case serviceStopped
        case setupRequired
        case serviceIssue

        public var title: String {
            switch self {
            case .serviceStarting: "Service starting"
            case .waitingForBoard: "Ready for board"
            case .boardConnected: "Board connected"
            case .boardDisconnected: "Board disconnected"
            case .serviceStopped: "Service stopped"
            case .setupRequired: "Setup required"
            case .serviceIssue: "Service needs attention"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    public let date: Date

    public init(id: UUID = UUID(), kind: Kind, date: Date) {
        self.id = id
        self.kind = kind
        self.date = date
    }
}

public struct ConnectionHistoryLog: Codable, Equatable, Sendable {
    public private(set) var entries: [ConnectionHistoryEntry]
    public let capacity: Int

    public init(entries: [ConnectionHistoryEntry] = [], capacity: Int = 24) {
        self.capacity = max(1, capacity)
        self.entries = Array(entries.sorted { $0.date > $1.date }.prefix(self.capacity))
    }

    public mutating func record(_ kind: ConnectionHistoryEntry.Kind, at date: Date = Date()) {
        if let newest = entries.first,
           newest.kind == kind,
           abs(newest.date.timeIntervalSince(date)) < 2 {
            return
        }

        entries.insert(ConnectionHistoryEntry(kind: kind, date: date), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data?, capacity: Int = 24) -> ConnectionHistoryLog {
        guard let data,
              let decoded = try? JSONDecoder().decode(ConnectionHistoryLog.self, from: data) else {
            return ConnectionHistoryLog(capacity: capacity)
        }
        return ConnectionHistoryLog(entries: decoded.entries, capacity: capacity)
    }
}
