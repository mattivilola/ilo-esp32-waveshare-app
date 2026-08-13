import Foundation

public let boardProtocolVersion = 1
public let boardProtocolMaximumFrameBytes = 65_536
public let screenCaptureProtocolVersion = 1
public let screenCaptureWidth = 1_024
public let screenCaptureHeight = 600
public let screenCaptureMaximumChunkBytes = 2_880
public let screenCaptureRGB565Bytes = screenCaptureWidth * screenCaptureHeight * 2
public let screenCaptureChunkCount =
    (screenCaptureRGB565Bytes + screenCaptureMaximumChunkBytes - 1) / screenCaptureMaximumChunkBytes
public let codexChatProtocolVersion = 1
public let codexChatMaximumMessages = 6
public let codexChatMaximumMessageCharacters = 360

public enum BoardDisplayText {
    /// LVGL's bundled Montserrat fonts intentionally cover a compact glyph set.
    /// Normalize host-provided copy before it crosses the wire so the board never
    /// renders replacement boxes for smart punctuation, diacritics, or emoji.
    public static func sanitized(_ value: String, maximum: Int) -> String {
        let punctuation = value
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "...")
            .replacingOccurrences(of: "\u{2022}", with: "/")
            .replacingOccurrences(of: "\u{00B7}", with: "/")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let folded = punctuation.folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let scalars = folded.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            if scalar.value >= 0x20, scalar.value <= 0x7E { return scalar }
            return CharacterSet.whitespacesAndNewlines.contains(scalar) ? " " : nil
        }
        let compact = String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(compact.prefix(maximum))
    }
}

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

public struct HostTimeStatus: Codable, Equatable, Sendable {
    public let utcOffsetSeconds: Int
    public let timezoneAbbreviation: String

    public init(date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) {
        utcOffsetSeconds = min(max(timeZone.secondsFromGMT(for: date), -50_400), 50_400)
        let raw = timeZone.abbreviation(for: date) ?? "UTC"
        let allowed = raw.unicodeScalars.filter {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "+-:".unicodeScalars.contains($0))
        }
        let normalized = String(String.UnicodeScalarView(allowed.prefix(7)))
        timezoneAbbreviation = normalized.isEmpty ? "UTC" : normalized
    }
}

public struct WeatherLocation: Codable, Equatable, Sendable {
    public let name: String
    public let latitude: Double
    public let longitude: Double

    public init(name: String, latitude: Double, longitude: Double) {
        let safeName = BoardDisplayText.sanitized(name, maximum: 40)
        self.name = safeName.isEmpty ? "Current location" : safeName
        self.latitude = min(max((latitude * 100).rounded() / 100, -90), 90)
        self.longitude = min(max((longitude * 100).rounded() / 100, -180), 180)
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

public enum CodexChatRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

public struct CodexChatMessage: Codable, Equatable, Sendable {
    public let role: CodexChatRole
    public let text: String

    public init(role: CodexChatRole, text: String) {
        self.role = role
        self.text = text
    }
}

public enum CodexChatStatus: String, Codable, Equatable, Sendable {
    case ready
    case unavailable
    case busy
    case failed
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
    public let xNewsEnabled: Bool
    public let newsFeed: NewsFeedSnapshot?
    public let macPower: MacPowerStatus?
    public let hostTime: HostTimeStatus?
    public let weatherLocation: WeatherLocation?
    public let companionVersion: String?

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case revision
        case generatedAt
        case hostState
        case capabilities
        case tasks
        case xNewsEnabled
        case newsFeed
        case macPower
        case hostTime
        case weatherLocation
        case companionVersion
    }

    public init(
        revision: UInt64,
        generatedAt: Date = Date(),
        hostState: HostState = .online,
        tasks: [TaskCard],
        codexContinueEnabled: Bool = false,
        xNewsEnabled: Bool? = nil,
        newsFeed: NewsFeedSnapshot? = nil,
        macPower: MacPowerStatus? = nil,
        hostTime: HostTimeStatus? = nil,
        weatherLocation: WeatherLocation? = nil,
        companionVersion: String? = nil
    ) {
        self.protocolVersion = boardProtocolVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.hostState = hostState
        var capabilities = ["tasks.read", "tasks.chat.read"]
        if codexContinueEnabled { capabilities.append("tasks.continue.fixed") }
        capabilities.append(contentsOf: ["macPower.read", "hostTime.read"])
        if newsFeed != nil { capabilities.append("xNews.read") }
        self.capabilities = capabilities
        self.tasks = Array(tasks.prefix(12))
        self.xNewsEnabled = xNewsEnabled ?? (newsFeed != nil)
        self.newsFeed = newsFeed
        self.macPower = macPower
        self.hostTime = hostTime
        self.weatherLocation = weatherLocation
        self.companionVersion = companionVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        revision = try container.decode(UInt64.self, forKey: .revision)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        hostState = try container.decode(HostState.self, forKey: .hostState)
        capabilities = try container.decode([String].self, forKey: .capabilities)
        tasks = try container.decode([TaskCard].self, forKey: .tasks)
        newsFeed = try container.decodeIfPresent(NewsFeedSnapshot.self, forKey: .newsFeed)
        xNewsEnabled = try container.decodeIfPresent(Bool.self, forKey: .xNewsEnabled)
            ?? (newsFeed != nil)
        macPower = try container.decodeIfPresent(MacPowerStatus.self, forKey: .macPower)
        hostTime = try container.decodeIfPresent(HostTimeStatus.self, forKey: .hostTime)
        weatherLocation = try container.decodeIfPresent(WeatherLocation.self, forKey: .weatherLocation)
        companionVersion = try container.decodeIfPresent(String.self, forKey: .companionVersion)
    }
}

public struct ClientMessage: Codable, Equatable, Sendable {
    public let type: String
    public let protocolVersion: Int?
    public let boardID: String?
    public let firmwareVersion: String?

    public init(
        type: String,
        protocolVersion: Int? = nil,
        boardID: String? = nil,
        firmwareVersion: String? = nil
    ) {
        self.type = type
        self.protocolVersion = protocolVersion
        self.boardID = boardID
        self.firmwareVersion = firmwareVersion
    }
}

public struct HelloAcknowledgement: Encodable, Equatable, Sendable {
    public let type = "helloAck"
    public let protocolVersion = boardProtocolVersion
    public let capabilities = [
        "tasks.read",
        "tasks.chat.read",
        "tasks.continue.fixed",
        "macPower.read",
        "xNews.refresh.request",
    ]
    public let serverTime: Date

    public init(serverTime: Date = Date()) {
        self.serverTime = serverTime
    }
}

public struct CodexChatRequest: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let requestID: String
    public let taskID: String

    public init(requestID: String, taskID: String) {
        type = "codexChatRequest"
        version = codexChatProtocolVersion
        self.requestID = requestID
        self.taskID = taskID
    }
}

public struct CodexChatDetailMessage: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let requestID: String
    public let taskID: String
    public let status: CodexChatStatus
    public let title: String
    public let messages: [CodexChatMessage]
    public let message: String?

    public init(
        requestID: String,
        taskID: String,
        status: CodexChatStatus,
        title: String,
        messages: [CodexChatMessage] = [],
        message: String? = nil
    ) {
        type = "codexChatDetail"
        version = codexChatProtocolVersion
        self.requestID = requestID
        self.taskID = taskID
        self.status = status
        self.title = title
        self.messages = Array(messages.prefix(codexChatMaximumMessages))
        self.message = message
    }
}

public struct CodexContinueRequest: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let requestID: String
    public let taskID: String
    public let action: String

    public init(requestID: String, taskID: String) {
        type = "codexContinueRequest"
        version = 1
        self.requestID = requestID
        self.taskID = taskID
        action = "continue"
    }
}

public enum CodexContinueStatus: String, Codable, Equatable, Sendable {
    case accepted
    case unavailable
    case busy
    case rejected
    case failed
}

public struct CodexContinueStatusMessage: Codable, Equatable, Sendable {
    public let type: String
    public let version: Int
    public let requestID: String
    public let status: CodexContinueStatus
    public let message: String

    public init(requestID: String, status: CodexContinueStatus, message: String) {
        type = "codexContinueStatus"
        version = 1
        self.requestID = requestID
        self.status = status
        self.message = message
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
