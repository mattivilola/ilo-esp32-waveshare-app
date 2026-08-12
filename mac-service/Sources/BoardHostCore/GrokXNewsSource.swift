import Darwin
import BoardProtocol
import Foundation

private func writeXNewsData(_ data: Data, to url: URL) throws {
    let target = url.standardizedFileURL.path
    let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
    let isTemporary = target == temporaryRoot || target.hasPrefix(temporaryRoot + "/")
    try data.write(
        to: url,
        options: isTemporary ? [.atomic] : [.atomic, .completeFileProtection]
    )
}

public enum XNewsCategory: String, Codable, CaseIterable, Sendable {
    case ai = "AI"
    case robotics = "Robotics"
}

public enum XNewsConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
}

public struct XNewsCitation: Codable, Equatable, Sendable {
    public let handle: String
    public let postedAt: Date
    public let xURL: URL

    public init(handle: String, postedAt: Date, xURL: URL) {
        self.handle = handle
        self.postedAt = postedAt
        self.xURL = xURL
    }
}

public struct XNewsStory: Codable, Equatable, Sendable {
    public let title: String
    public let summary: String
    public let category: XNewsCategory
    public let confidence: XNewsConfidence
    public let sources: [XNewsCitation]

    public init(
        title: String,
        summary: String,
        category: XNewsCategory,
        confidence: XNewsConfidence,
        sources: [XNewsCitation]
    ) {
        self.title = title
        self.summary = summary
        self.category = category
        self.confidence = confidence
        self.sources = sources
    }
}

public struct XNewsFeed: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let stories: [XNewsStory]

    public init(generatedAt: Date, stories: [XNewsStory]) {
        self.generatedAt = generatedAt
        self.stories = stories
    }
}

public enum XNewsRefreshCadence: String, Codable, CaseIterable, Sendable {
    case off
    case daily
    case morningAndAfternoon

    public var scheduledLocalHours: [Int] {
        switch self {
        case .off: []
        case .daily: [8]
        case .morningAndAfternoon: [8, 14]
        }
    }
}

public struct XNewsRefreshPolicy: Equatable, Sendable {
    public static let manualCooldown: TimeInterval = 15 * 60
    public let cadence: XNewsRefreshCadence

    public init(cadence: XNewsRefreshCadence = .daily) {
        self.cadence = cadence
    }

    public func nextAutomaticRefresh(after date: Date, calendar: Calendar = .current) -> Date? {
        guard !cadence.scheduledLocalHours.isEmpty else { return nil }
        let startOfDay = calendar.startOfDay(for: date)
        for dayOffset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else { continue }
            for hour in cadence.scheduledLocalHours {
                guard let candidate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                      candidate > date
                else {
                    continue
                }
                return candidate
            }
        }
        return nil
    }

    public func allowsManualRefresh(lastAttempt: Date?, now: Date = Date()) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= Self.manualCooldown
    }
}

public struct XNewsRefreshSettings: Codable, Equatable, Sendable {
    public let cadence: XNewsRefreshCadence
    public let consentVersion: Int
    public let lastAttemptAt: Date?

    public init(cadence: XNewsRefreshCadence = .off, consentVersion: Int = 1, lastAttemptAt: Date? = nil) {
        self.cadence = cadence
        self.consentVersion = consentVersion
        self.lastAttemptAt = lastAttemptAt
    }
}

public struct XNewsRefreshSettingsStore: Sendable {
    public let url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ILO Board Host/x-news-settings.json")
    }

    public func load() -> XNewsRefreshSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(XNewsRefreshSettings.self, from: data),
              settings.consentVersion == 1
        else {
            return XNewsRefreshSettings()
        }
        return settings
    }

    public func save(_ settings: XNewsRefreshSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeXNewsData(encoder.encode(settings), to: url)
    }
}

public enum GrokXNewsError: Error, LocalizedError, Sendable {
    case executableNotFound
    case explicitConsentRequired
    case processFailed(String)
    case timedOut
    case malformedEnvelope
    case malformedFeed
    case invalidFeed(String)
    case noCachedFeed
    case refreshCooldown

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Grok CLI was not found. Install and authenticate it, or set ILO_BOARD_GROK_PATH."
        case .explicitConsentRequired:
            "X news is disabled. Re-run with explicit consent after reviewing the Grok prompt and permissions."
        case let .processFailed(message):
            "Grok X-news request failed: \(message)"
        case .timedOut:
            "Grok X-news request exceeded the three-minute limit."
        case .malformedEnvelope:
            "Grok did not return its expected outer JSON envelope."
        case .malformedFeed:
            "Grok did not return one strict X-news JSON document. The previous verified feed was preserved."
        case let .invalidFeed(reason):
            "Grok X-news output was rejected: \(reason). The previous verified feed was preserved."
        case .noCachedFeed:
            "No verified X-news feed is cached yet."
        case .refreshCooldown:
            "Wait 15 minutes before starting another X-news refresh."
        }
    }
}

public enum GrokExecutableResolver {
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidates = [String]()
        if let configured = environment["ILO_BOARD_GROK_PATH"], !configured.isEmpty {
            candidates.append(configured)
        }
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/grok" })
        }
        candidates.append(contentsOf: [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/grok",
            "/opt/homebrew/bin/grok",
            "/usr/local/bin/grok",
        ])
        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}

public enum GrokXNewsContract {
    public static let maximumAge: TimeInterval = 24 * 60 * 60
    public static let maximumStories = 5
    public static let minimumStories = 2

    public static func prompt(now: Date) -> String {
        let until = formatDate(now)
        let since = formatDate(now.addingTimeInterval(-maximumAge))
        return """
        X news for AI + humanoid/robotics ONLY in this UTC window:
        - since: \(since)
        - until: \(until)
        - generated_at: \(until)

        Hard rules:
        1) Use keyword search with since:\(String(since.prefix(10))) until:\(String(until.prefix(10))).
        2) Use semantic search with from_date=\(since) to_date=\(until).
        3) Drop every post with a timestamp before \(since) or after \(until).
        4) Deduplicate stories. Skip items widely covered before this window unless the cited post contains a new development.
        5) Prefer primary-source posts and omit low-confidence stories.
        6) Return exactly one JSON object and no markdown or commentary.
        7) Include 2 to 5 unique topics; category must be exactly AI or Robotics and confidence exactly high or medium.
        8) Include 1 to 3 sources per topic. Every post_url must be a direct cited URL shaped https://x.com/<handle>/status/<numeric-id>.
        Profile pages, home pages, search pages, missing citations, and invented URLs are forbidden.
        """
    }

    public static let jsonSchema = #"{"type":"object","additionalProperties":false,"required":["window","generated_at","topics"],"properties":{"window":{"type":"object","additionalProperties":false,"required":["since","until"],"properties":{"since":{"type":"string"},"until":{"type":"string"}}},"generated_at":{"type":"string"},"topics":{"type":"array","minItems":2,"maxItems":5,"items":{"type":"object","additionalProperties":false,"required":["category","headline","summary","confidence","posted_at","sources"],"properties":{"category":{"enum":["AI","Robotics"]},"headline":{"type":"string","minLength":1,"maxLength":70},"summary":{"type":"string","minLength":1,"maxLength":220},"confidence":{"enum":["high","medium"]},"posted_at":{"type":"string"},"sources":{"type":"array","minItems":1,"maxItems":3,"items":{"type":"object","additionalProperties":false,"required":["handle","post_url"],"properties":{"handle":{"type":"string","pattern":"^@[A-Za-z0-9_]{1,15}$"},"post_url":{"type":"string","pattern":"^https://x[.]com/[A-Za-z0-9_]{1,15}/status/[0-9]+$"}}}}}}}}}"#

    public static func processArguments(now: Date) -> [String] {
        [
            "-p", prompt(now: now),
            "--output-format", "json",
            "--json-schema", jsonSchema,
            "--max-turns", "15",
            "--no-subagents",
            "--no-memory",
            "--yolo",
        ]
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

public enum GrokXNewsParser {
    private struct CLIEnvelope: Decodable {
        let text: String
    }

    private struct RawFeed: Decodable {
        let window: RawWindow
        let generatedAt: String
        let topics: [RawTopic]

        enum CodingKeys: String, CodingKey {
            case window
            case generatedAt = "generated_at"
            case topics
        }
    }

    private struct RawWindow: Decodable {
        let since: String
        let until: String
    }

    private struct RawTopic: Decodable {
        let category: String
        let headline: String
        let summary: String
        let confidence: String
        let postedAt: String
        let sources: [RawSource]

        enum CodingKeys: String, CodingKey {
            case category, headline, summary, confidence, sources
            case postedAt = "posted_at"
        }
    }

    private struct RawSource: Decodable {
        let handle: String
        let postURL: String

        enum CodingKeys: String, CodingKey {
            case handle
            case postURL = "post_url"
        }
    }

    public static func parse(grokOutput: Data, now: Date = Date()) throws -> XNewsFeed {
        guard let envelope = try? JSONDecoder().decode(CLIEnvelope.self, from: grokOutput) else {
            throw GrokXNewsError.malformedEnvelope
        }
        let documents = JSONDocumentScanner.documents(in: envelope.text)
        guard !documents.isEmpty else {
            throw GrokXNewsError.malformedFeed
        }
        var validFeeds = [XNewsFeed]()
        var firstValidationError: Error?
        for document in documents {
            guard let data = document.data(using: .utf8),
                  let raw = try? JSONDecoder().decode(RawFeed.self, from: data)
            else {
                continue
            }
            do {
                validFeeds.append(try validate(raw, now: now))
            } catch {
                firstValidationError = firstValidationError ?? error
            }
        }
        if !validFeeds.isEmpty { return merge(validFeeds) }
        if let firstValidationError { throw firstValidationError }
        throw GrokXNewsError.malformedFeed
    }

    private static func merge(_ feeds: [XNewsFeed]) -> XNewsFeed {
        var seenURLs = Set<String>()
        var seenHeadlines = Set<String>()
        var stories = [XNewsStory]()
        for feed in feeds.reversed() {
            for story in feed.stories {
                let headlineKey = story.title.lowercased()
                    .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                guard seenHeadlines.insert(headlineKey).inserted else { continue }
                let newSources = story.sources.filter { seenURLs.insert($0.xURL.absoluteString).inserted }
                guard !newSources.isEmpty else { continue }
                stories.append(XNewsStory(
                    title: story.title,
                    summary: story.summary,
                    category: story.category,
                    confidence: story.confidence,
                    sources: newSources
                ))
                if stories.count == GrokXNewsContract.maximumStories { break }
            }
            if stories.count == GrokXNewsContract.maximumStories { break }
        }
        return XNewsFeed(
            generatedAt: feeds.map(\.generatedAt).max() ?? Date.distantPast,
            stories: stories
        )
    }

    private static func validate(_ raw: RawFeed, now: Date) throws -> XNewsFeed {
        guard let since = parseDate(raw.window.since),
              let until = parseDate(raw.window.until),
              let generatedAt = parseDate(raw.generatedAt),
              abs(since.timeIntervalSince(now.addingTimeInterval(-GrokXNewsContract.maximumAge))) <= 15 * 60,
              abs(until.timeIntervalSince(now)) <= 15 * 60,
              abs(generatedAt.timeIntervalSince(now)) <= 15 * 60,
              since < until
        else {
            throw GrokXNewsError.invalidFeed("window and generated_at must match the requested rolling 24 hours")
        }
        guard (GrokXNewsContract.minimumStories...GrokXNewsContract.maximumStories).contains(raw.topics.count) else {
            throw GrokXNewsError.invalidFeed("expected 2 to 5 stories")
        }

        var seenURLs = Set<String>()
        var stories = [XNewsStory]()
        var firstTopicError: Error?
        for topic in raw.topics {
            do {
                let story = try validate(topic, since: since, until: until, now: now, seenURLs: &seenURLs)
                stories.append(story)
            } catch {
                firstTopicError = firstTopicError ?? error
            }
        }
        guard (GrokXNewsContract.minimumStories...GrokXNewsContract.maximumStories).contains(stories.count) else {
            if let firstTopicError { throw firstTopicError }
            throw GrokXNewsError.invalidFeed("expected at least 2 fully verified stories")
        }
        return XNewsFeed(generatedAt: generatedAt, stories: stories)
    }

    private static func validate(
        _ topic: RawTopic,
        since: Date,
        until: Date,
        now: Date,
        seenURLs: inout Set<String>
    ) throws -> XNewsStory {
            let title = try bounded(topic.headline, field: "headline", maximum: 70)
            let summary = try bounded(topic.summary, field: "summary", maximum: 220)
            guard let category = XNewsCategory(rawValue: topic.category) else {
                throw GrokXNewsError.invalidFeed("category must be AI or Robotics")
            }
            guard let confidence = XNewsConfidence(rawValue: topic.confidence) else {
                throw GrokXNewsError.invalidFeed("confidence must be high or medium")
            }
            guard let claimedPostedAt = parseDate(topic.postedAt),
                  claimedPostedAt >= since,
                  claimedPostedAt <= until
            else {
                throw GrokXNewsError.invalidFeed("posted_at is outside the requested window")
            }
            guard (1...3).contains(topic.sources.count) else {
                throw GrokXNewsError.invalidFeed("every story needs 1 to 3 sources")
            }
            var topicURLs = Set<String>()
            let citations = try topic.sources.map { source -> XNewsCitation in
                guard let parsed = directStatusURL(source.postURL) else {
                    throw GrokXNewsError.invalidFeed("every post_url must be a direct x.com status URL")
                }
                let expectedHandle = "@\(parsed.handle)"
                guard source.handle.caseInsensitiveCompare(expectedHandle) == .orderedSame else {
                    throw GrokXNewsError.invalidFeed("source handle must match its status URL")
                }
                guard parsed.postedAt <= now,
                      now.timeIntervalSince(parsed.postedAt) <= GrokXNewsContract.maximumAge
                else {
                    throw GrokXNewsError.invalidFeed("X status ID is outside the last 24 hours")
                }
                guard abs(parsed.postedAt.timeIntervalSince(claimedPostedAt)) <= 10 * 60 else {
                    throw GrokXNewsError.invalidFeed("posted_at does not agree with the X status ID")
                }
                guard !seenURLs.contains(parsed.url.absoluteString),
                      topicURLs.insert(parsed.url.absoluteString).inserted
                else {
                    throw GrokXNewsError.invalidFeed("duplicate X status URL")
                }
                return XNewsCitation(handle: expectedHandle, postedAt: parsed.postedAt, xURL: parsed.url)
            }
            seenURLs.formUnion(topicURLs)
            return XNewsStory(title: title, summary: summary, category: category, confidence: confidence, sources: citations)
    }

    private static func bounded(_ value: String, field: String, maximum: Int) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !normalized.contains("\n"),
              !normalized.contains("\r"),
              normalized.count <= maximum
        else {
            throw GrokXNewsError.invalidFeed("\(field) is empty, multiline, or too long")
        }
        return normalized
    }

    private static func directStatusURL(_ value: String) -> (url: URL, handle: String, postedAt: Date)? {
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              components.host?.lowercased() == "x.com",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil
        else {
            return nil
        }
        let path = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard path.count == 3,
              path[1] == "status",
              (1...15).contains(path[0].count),
              path[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
              path[2].count >= 10,
              path[2].allSatisfy(\.isNumber)
        else {
            return nil
        }
        guard let url = components.url,
              let statusID = UInt64(path[2]),
              statusID > 0
        else {
            return nil
        }
        let milliseconds = (statusID >> 22) + 1_288_834_974_657
        return (url, String(path[0]), Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000))
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: value) { return parsed }
        return ISO8601DateFormatter().date(from: value)
    }
}

public struct XNewsFeedCache: Sendable {
    public let url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ILO Board Host/x-news.json")
    }

    public func load(now: Date = Date()) throws -> XNewsFeed {
        let feed = try loadIncludingStale()
        guard now.timeIntervalSince(feed.generatedAt) >= -10 * 60,
              now.timeIntervalSince(feed.generatedAt) <= GrokXNewsContract.maximumAge
        else {
            throw GrokXNewsError.noCachedFeed
        }
        return feed
    }

    public func loadIncludingStale() throws -> XNewsFeed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let feed = try? decoder.decode(XNewsFeed.self, from: data)
        else {
            throw GrokXNewsError.noCachedFeed
        }
        return feed
    }

    public func save(_ feed: XNewsFeed) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeXNewsData(encoder.encode(feed), to: url)
    }
}

public enum XNewsWireMapper {
    public static func snapshot(from feed: XNewsFeed) -> NewsFeedSnapshot {
        NewsFeedSnapshot(
            generatedAt: feed.generatedAt,
            stories: feed.stories.enumerated().map { index, story in
                NewsStory(
                    id: story.sources.first?.xURL.absoluteString ?? "story-\(index)",
                    category: story.category.rawValue,
                    headline: boardSafeText(story.title),
                    summary: boardSafeText(story.summary),
                    confidence: story.confidence.rawValue,
                    sources: story.sources.map {
                        NewsCitation(handle: $0.handle, postedAt: $0.postedAt, postURL: $0.xURL.absoluteString)
                    }
                )
            }
        )
    }

    /// LVGL's compact built-in Montserrat fonts cover a deliberately small glyph set.
    /// Keep the verified cache unchanged while making the board wire text predictable.
    static func boardSafeText(_ value: String) -> String {
        let punctuation = value
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "...")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        return punctuation.folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    public static func cachedSnapshot(now: Date = Date(), cache: XNewsFeedCache = XNewsFeedCache()) -> NewsFeedSnapshot? {
        guard let feed = try? cache.load(now: now) else { return nil }
        return snapshot(from: feed)
    }
}

public struct GrokXNewsSource: Sendable {
    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
    }

    public let cache: XNewsFeedCache
    public let environment: [String: String]

    public init(
        cache: XNewsFeedCache = XNewsFeedCache(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.cache = cache
        self.environment = environment
    }

    public func refresh(explicitlyAllowsGrokTools: Bool, now: Date = Date()) throws -> XNewsFeed {
        guard explicitlyAllowsGrokTools else { throw GrokXNewsError.explicitConsentRequired }
        guard let executable = GrokExecutableResolver.resolve(environment: environment) else {
            throw GrokXNewsError.executableNotFound
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ilo-board-grok-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let stdoutURL = temporaryDirectory.appendingPathComponent("stdout.json")
        let stderrURL = temporaryDirectory.appendingPathComponent("stderr.txt")
        _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = GrokXNewsContract.processArguments(now: now)
        process.environment = environment
        process.currentDirectoryURL = temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr

        let processBox = ProcessBox(process)
        let timeout = DispatchWorkItem {
            if processBox.process.isRunning {
                processBox.process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 180, execute: timeout)
        do {
            try process.run()
        } catch {
            timeout.cancel()
            throw GrokXNewsError.processFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        let didTimeOut = !timeout.isCancelled && process.terminationStatus == SIGTERM
        timeout.cancel()
        try stdout.synchronize()
        try stderr.synchronize()

        if didTimeOut { throw GrokXNewsError.timedOut }
        guard process.terminationStatus == 0 else {
            throw GrokXNewsError.processFailed("exit status \(process.terminationStatus)")
        }

        let outputSize = try stdoutURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard outputSize <= 1_000_000 else {
            throw GrokXNewsError.invalidFeed("response exceeds the one-megabyte safety limit")
        }
        let candidate = try GrokXNewsParser.parse(grokOutput: Data(contentsOf: stdoutURL), now: now)
        let feed = deduplicating(candidate, against: try? cache.loadIncludingStale())
        guard !feed.stories.isEmpty else {
            throw GrokXNewsError.invalidFeed("no newly cited development remains after cache deduplication")
        }
        try cache.save(feed)
        return feed
    }

    private func deduplicating(_ candidate: XNewsFeed, against previous: XNewsFeed?) -> XNewsFeed {
        let previousURLs = Set(previous?.stories.flatMap(\.sources).map { $0.xURL.absoluteString } ?? [])
        guard !previousURLs.isEmpty else { return candidate }
        return XNewsFeed(
            generatedAt: candidate.generatedAt,
            stories: candidate.stories.filter { story in
                story.sources.contains { !previousURLs.contains($0.xURL.absoluteString) }
            }
        )
    }
}

public actor XNewsRefreshCoordinator {
    public static let shared = XNewsRefreshCoordinator()

    private let settingsStore: XNewsRefreshSettingsStore
    private let cache: XNewsFeedCache
    private var refreshInFlight = false
    private var lastActivity: XNewsRefreshActivity = .idle

    public init(
        settingsStore: XNewsRefreshSettingsStore = XNewsRefreshSettingsStore(),
        cache: XNewsFeedCache = XNewsFeedCache()
    ) {
        self.settingsStore = settingsStore
        self.cache = cache
    }

    public func run() async {
        while !Task.isCancelled {
            considerRefresh()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    public func requestManualRefresh(now: Date = Date()) async -> XNewsManualRefreshOutcome {
        guard !refreshInFlight else { return .busy }
        let settings = settingsStore.load()
        guard settings.consentVersion == 1, settings.cadence != .off else {
            lastActivity = .disabled
            return .disabled
        }
        let policy = XNewsRefreshPolicy(cadence: settings.cadence)
        guard policy.allowsManualRefresh(lastAttempt: settings.lastAttemptAt, now: now) else {
            lastActivity = .cooldown(until: (settings.lastAttemptAt ?? now).addingTimeInterval(XNewsRefreshPolicy.manualCooldown))
            return .cooldown
        }
        do {
            try settingsStore.save(XNewsRefreshSettings(
                cadence: settings.cadence,
                consentVersion: settings.consentVersion,
                lastAttemptAt: now
            ))
        } catch {
            lastActivity = .failed(at: now)
            return .failed
        }

        refreshInFlight = true
        lastActivity = .fetching(startedAt: now)
        defer { refreshInFlight = false }
        let source = GrokXNewsSource(cache: cache)
        do {
            _ = try await Task.detached(priority: .utility) {
                try source.refresh(explicitlyAllowsGrokTools: true, now: now)
            }.value
            lastActivity = .updated(at: Date())
            return .updated
        } catch {
            lastActivity = .failed(at: Date())
            return .failed
        }
    }

    public func activity(now: Date = Date()) -> XNewsRefreshActivity {
        if refreshInFlight {
            if case .fetching = lastActivity { return lastActivity }
            return .fetching(startedAt: now)
        }
        if case let .cooldown(until) = lastActivity, until <= now {
            lastActivity = .idle
        }
        return lastActivity
    }

    public func considerRefresh(now: Date = Date(), calendar: Calendar = .current) {
        guard !refreshInFlight else { return }
        let settings = settingsStore.load()
        guard settings.consentVersion == 1, settings.cadence != .off else { return }
        let policy = XNewsRefreshPolicy(cadence: settings.cadence)
        guard policy.allowsManualRefresh(lastAttempt: settings.lastAttemptAt, now: now) else { return }
        let previous = try? cache.loadIncludingStale()
        let mostRecentReference = [previous?.generatedAt, settings.lastAttemptAt].compactMap { $0 }.max()
        let isDue = mostRecentReference == nil || policy.nextAutomaticRefresh(
            after: mostRecentReference ?? now,
            calendar: calendar
        ).map { $0 <= now } == true
        guard isDue else { return }

        try? settingsStore.save(XNewsRefreshSettings(
            cadence: settings.cadence,
            consentVersion: settings.consentVersion,
            lastAttemptAt: now
        ))
        refreshInFlight = true
        lastActivity = .fetching(startedAt: now)
        let source = GrokXNewsSource(cache: cache)
        Task.detached(priority: .utility) { [weak self] in
            do {
                _ = try source.refresh(explicitlyAllowsGrokTools: true)
                await self?.refreshFinished(.updated(at: Date()))
            } catch {
                await self?.refreshFinished(.failed(at: Date()))
            }
        }
    }

    private func refreshFinished(_ activity: XNewsRefreshActivity) {
        refreshInFlight = false
        lastActivity = activity
    }
}

public enum XNewsRefreshActivity: Equatable, Sendable {
    case idle
    case fetching(startedAt: Date)
    case updated(at: Date)
    case disabled
    case cooldown(until: Date)
    case failed(at: Date)
}

public enum XNewsManualRefreshOutcome: String, Equatable, Sendable {
    case updated
    case disabled
    case cooldown
    case busy
    case failed
}

private enum JSONDocumentScanner {
    static func documents(in value: String) -> [String] {
        var results = [String]()
        var documentStart: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                if depth == 0 { documentStart = index }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let start = documentStart {
                    results.append(String(value[start...index]))
                    documentStart = nil
                }
            }
            index = value.index(after: index)
        }
        return results
    }

}
