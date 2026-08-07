import Foundation

public let boardProtocolVersion = 1
public let boardProtocolMaximumFrameBytes = 65_536

public enum TaskState: String, Codable, Sendable, CaseIterable {
    case active
    case waiting
    case completed
    case failed
    case idle
}

public enum AttentionKind: String, Codable, Sendable, CaseIterable {
    case none
    case question
    case approval
}

public enum HostState: String, Codable, Sendable {
    case online
    case sleeping
    case degraded
}

public struct TaskCard: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let state: TaskState
    public let attentionKind: AttentionKind
    public let updatedAt: Date
    public let shortSummary: String

    public init(
        id: String,
        title: String,
        state: TaskState,
        attentionKind: AttentionKind,
        updatedAt: Date,
        shortSummary: String
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.attentionKind = attentionKind
        self.updatedAt = updatedAt
        self.shortSummary = shortSummary
    }
}

public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let revision: UInt64
    public let generatedAt: Date
    public let hostState: HostState
    public let capabilities: [String]
    public let tasks: [TaskCard]

    public init(
        revision: UInt64,
        generatedAt: Date = Date(),
        hostState: HostState = .online,
        tasks: [TaskCard]
    ) {
        self.protocolVersion = boardProtocolVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.hostState = hostState
        self.capabilities = ["tasks.read"]
        self.tasks = Array(tasks.prefix(12))
    }
}

public struct ClientMessage: Codable, Equatable, Sendable {
    public let type: String
    public let protocolVersion: Int?
    public let boardID: String?

    public init(type: String, protocolVersion: Int? = nil, boardID: String? = nil) {
        self.type = type
        self.protocolVersion = protocolVersion
        self.boardID = boardID
    }
}

public struct HelloAcknowledgement: Encodable, Equatable, Sendable {
    public let type = "helloAck"
    public let protocolVersion = boardProtocolVersion
    public let capabilities = ["tasks.read"]
    public let serverTime: Date

    public init(serverTime: Date = Date()) {
        self.serverTime = serverTime
    }
}

public struct SnapshotMessage: Encodable, Equatable, Sendable {
    public let type = "snapshot"
    public let snapshot: DashboardSnapshot

    public init(snapshot: DashboardSnapshot) {
        self.snapshot = snapshot
    }
}

public struct ErrorMessage: Encodable, Equatable, Sendable {
    public let type = "error"
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public enum ProtocolJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
