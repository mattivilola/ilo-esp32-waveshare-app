import Foundation

public let boardProtocolVersion = 1
public let boardProtocolMaximumFrameBytes = 65_536
public let screenCaptureProtocolVersion = 1
public let screenCaptureWidth = 1_024
public let screenCaptureHeight = 600
public let screenCaptureMaximumChunkBytes = 12_288
public let screenCaptureRGB565Bytes = screenCaptureWidth * screenCaptureHeight * 2
public let screenCaptureChunkCount =
    (screenCaptureRGB565Bytes + screenCaptureMaximumChunkBytes - 1) / screenCaptureMaximumChunkBytes

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

public enum MacPowerState: String, Codable, Sendable, CaseIterable {
    case battery
    case charging
    case powerAdapter
    case full
}

public struct MacPowerStatus: Codable, Equatable, Sendable {
    public let levelPercent: Int
    public let state: MacPowerState

    public init(levelPercent: Int, state: MacPowerState) {
        self.levelPercent = min(max(levelPercent, 0), 100)
        self.state = state
    }
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

public struct NewsCitation: Codable, Equatable, Sendable {
    public let handle: String
    public let postedAt: Date
    public let postURL: String

    public init(handle: String, postedAt: Date, postURL: String) {
        self.handle = handle
        self.postedAt = postedAt
        self.postURL = postURL
    }
}

public struct NewsStory: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let category: String
    public let headline: String
    public let summary: String
    public let confidence: String
    public let sources: [NewsCitation]

    public init(
        id: String,
        category: String,
        headline: String,
        summary: String,
        confidence: String,
        sources: [NewsCitation]
    ) {
        self.id = id
        self.category = category
        self.headline = headline
        self.summary = summary
        self.confidence = confidence
        self.sources = Array(sources.prefix(3))
    }
}

public struct NewsFeedSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let stories: [NewsStory]

    public init(generatedAt: Date, stories: [NewsStory]) {
        self.generatedAt = generatedAt
        self.stories = Array(stories.prefix(5))
    }
}

public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let revision: UInt64
    public let generatedAt: Date
    public let hostState: HostState
    public let capabilities: [String]
    public let tasks: [TaskCard]
    public let newsFeed: NewsFeedSnapshot?
    public let macPower: MacPowerStatus?

    public init(
        revision: UInt64,
        generatedAt: Date = Date(),
        hostState: HostState = .online,
        tasks: [TaskCard],
        newsFeed: NewsFeedSnapshot? = nil,
        macPower: MacPowerStatus? = nil
    ) {
        self.protocolVersion = boardProtocolVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.hostState = hostState
        self.capabilities = newsFeed == nil
            ? ["tasks.read", "macPower.read"]
            : ["tasks.read", "macPower.read", "xNews.read"]
        self.tasks = Array(tasks.prefix(12))
        self.newsFeed = newsFeed
        self.macPower = macPower
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
    public let capabilities = ["tasks.read", "macPower.read", "xNews.refresh.request"]
    public let serverTime: Date

    public init(serverTime: Date = Date()) {
        self.serverTime = serverTime
    }
}

public struct XNewsRefreshRequest: Codable, Equatable, Sendable {
    public let type: String
    public let requestID: String

    public init(requestID: String) {
        type = "xNewsRefreshRequest"
        self.requestID = requestID
    }
}

public enum XNewsRefreshStatus: String, Codable, Equatable, Sendable {
    case fetching
    case updated
    case disabled
    case cooldown
    case busy
    case failed
}

public struct XNewsRefreshStatusMessage: Codable, Equatable, Sendable {
    public let type: String
    public let requestID: String
    public let status: XNewsRefreshStatus
    public let message: String

    public init(requestID: String, status: XNewsRefreshStatus, message: String) {
        type = "xNewsRefreshStatus"
        self.requestID = requestID
        self.status = status
        self.message = message
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

public struct MessageEnvelope: Codable, Equatable, Sendable {
    public let type: String

    public init(type: String) {
        self.type = type
    }
}

public struct ScreenCaptureRequest: Encodable, Equatable, Sendable {
    public let type = "screenCaptureRequest"
    public let version = screenCaptureProtocolVersion
    public let requestID: String
    public let format = "rgb565le"
    public let width = screenCaptureWidth
    public let height = screenCaptureHeight

    public init(requestID: String = UUID().uuidString.lowercased()) {
        self.requestID = requestID
    }
}

public struct ScreenCaptureBeginMessage: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let requestID: String
    public let format: String
    public let width: Int
    public let height: Int
    public let totalBytes: Int
    public let chunkBytes: Int
    public let chunkCount: Int

    public init(
        type: String,
        version: Int,
        requestID: String,
        format: String,
        width: Int,
        height: Int,
        totalBytes: Int,
        chunkBytes: Int,
        chunkCount: Int
    ) {
        self.type = type
        self.version = version
        self.requestID = requestID
        self.format = format
        self.width = width
        self.height = height
        self.totalBytes = totalBytes
        self.chunkBytes = chunkBytes
        self.chunkCount = chunkCount
    }
}

public struct ScreenCaptureChunkMessage: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let requestID: String
    public let sequence: Int
    public let offset: Int
    public let data: Data

    public init(type: String, version: Int, requestID: String, sequence: Int, offset: Int, data: Data) {
        self.type = type
        self.version = version
        self.requestID = requestID
        self.sequence = sequence
        self.offset = offset
        self.data = data
    }
}

public struct ScreenCaptureResultMessage: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let requestID: String
    public let status: String
    public let totalBytes: Int?
    public let sha256: String?
    public let errorCode: String?
    public let message: String?

    public init(
        type: String,
        version: Int,
        requestID: String,
        status: String,
        totalBytes: Int?,
        sha256: String?,
        errorCode: String?,
        message: String?
    ) {
        self.type = type
        self.version = version
        self.requestID = requestID
        self.status = status
        self.totalBytes = totalBytes
        self.sha256 = sha256
        self.errorCode = errorCode
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
