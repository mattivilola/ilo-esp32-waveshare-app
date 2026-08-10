@testable import BoardHostCore
import Foundation
import Testing

private let referenceNow = ISO8601DateFormatter().date(from: "2026-08-10T09:00:00Z")!

@Test func grokResolverSupportsExplicitPath() {
    #expect(GrokExecutableResolver.resolve(environment: ["ILO_BOARD_GROK_PATH": "/bin/sh"])?.path == "/bin/sh")
}

@Test func strictGrokEnvelopeAcceptsBoundedRecentDirectStatusPosts() throws {
    let output = try grokEnvelope(feedDocuments: [
        feed(topics: [
            topic(
                category: "AI",
                headline: "New compact reasoning model",
                handle: "@example_ai",
                date: referenceNow.addingTimeInterval(-1_800)
            ),
            topic(
                category: "Robotics",
                headline: "Humanoid completes warehouse pilot",
                handle: "@examplebot",
                date: referenceNow.addingTimeInterval(-3_600)
            ),
        ]),
    ])

    let parsed = try GrokXNewsParser.parse(grokOutput: output, now: referenceNow)

    #expect(parsed.stories.count == 2)
    #expect(parsed.stories.map(\.category) == [.ai, .robotics])
    #expect(parsed.stories[0].sources[0].handle == "@example_ai")
    #expect(parsed.stories[0].sources[0].xURL.host == "x.com")
    let wire = XNewsWireMapper.snapshot(from: parsed)
    #expect(wire.stories.count == 2)
    #expect(wire.stories[0].sources[0].postURL.hasPrefix("https://x.com/example_ai/status/"))
}

@Test func oneValidDocumentCanBeSelectedFromConcatenatedGrokOutput() throws {
    let unsourced = feed(topics: [
        topic(category: "AI", headline: "Missing source one", handle: "@one", date: referenceNow, includeSource: false),
        topic(category: "Robotics", headline: "Missing source two", handle: "@two", date: referenceNow, includeSource: false),
    ])
    let valid = feed(topics: [
        topic(category: "AI", headline: "Verified one", handle: "@one", date: referenceNow.addingTimeInterval(-600)),
        topic(category: "Robotics", headline: "Verified two", handle: "@two", date: referenceNow.addingTimeInterval(-900)),
    ])

    let parsed = try GrokXNewsParser.parse(
        grokOutput: grokEnvelope(feedDocuments: [unsourced, valid]),
        now: referenceNow
    )

    #expect(parsed.stories.map(\.title) == ["Verified one", "Verified two"])
}

@Test func multipleValidDocumentsMergeDeterministicallyWhileUnsafeResultsAreRejected() throws {
    let valid = feed(topics: [
        topic(category: "AI", headline: "One", handle: "@one", date: referenceNow.addingTimeInterval(-600)),
        topic(category: "Robotics", headline: "Two", handle: "@two", date: referenceNow.addingTimeInterval(-900)),
    ])
    let merged = try GrokXNewsParser.parse(
        grokOutput: grokEnvelope(feedDocuments: [valid, valid]),
        now: referenceNow
    )
    #expect(merged.stories.count == 2)
    #expect(Set(merged.stories.flatMap(\.sources).map(\.xURL)).count == 2)

    var rootURL = valid
    var rootTopics = rootURL["topics"] as! [[String: Any]]
    var firstSources = rootTopics[0]["sources"] as! [[String: Any]]
    firstSources[0]["post_url"] = "https://x.com/"
    rootTopics[0]["sources"] = firstSources
    rootURL["topics"] = rootTopics
    #expect(throws: GrokXNewsError.self) {
        try GrokXNewsParser.parse(
            grokOutput: grokEnvelope(feedDocuments: [rootURL]),
            now: referenceNow
        )
    }

    let old = feed(topics: [
        topic(category: "AI", headline: "Old", handle: "@one", date: referenceNow.addingTimeInterval(-86_401)),
        topic(category: "Robotics", headline: "Recent", handle: "@two", date: referenceNow.addingTimeInterval(-900)),
    ])
    #expect(throws: GrokXNewsError.self) {
        try GrokXNewsParser.parse(
            grokOutput: grokEnvelope(feedDocuments: [old]),
            now: referenceNow
        )
    }
}

@Test func mismatchedHandleAndUnboundedTextAreRejected() throws {
    var mismatch = feed(topics: [
        topic(category: "AI", headline: "One", handle: "@one", date: referenceNow.addingTimeInterval(-600)),
        topic(category: "Robotics", headline: "Two", handle: "@two", date: referenceNow.addingTimeInterval(-900)),
    ])
    var topics = mismatch["topics"] as! [[String: Any]]
    var sources = topics[0]["sources"] as! [[String: Any]]
    sources[0]["handle"] = "@somebody_else"
    topics[0]["sources"] = sources
    mismatch["topics"] = topics
    #expect(throws: GrokXNewsError.self) {
        try GrokXNewsParser.parse(grokOutput: grokEnvelope(feedDocuments: [mismatch]), now: referenceNow)
    }

    var longText = feed(topics: [
        topic(category: "AI", headline: String(repeating: "x", count: 71), handle: "@one", date: referenceNow),
        topic(category: "Robotics", headline: "Two", handle: "@two", date: referenceNow),
    ])
    topics = longText["topics"] as! [[String: Any]]
    topics[0]["confidence"] = "low"
    longText["topics"] = topics
    #expect(throws: GrokXNewsError.self) {
        try GrokXNewsParser.parse(grokOutput: grokEnvelope(feedDocuments: [longText]), now: referenceNow)
    }
}

@Test func failedValidationDoesNotOverwriteLastGoodCache() throws {
    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-x-news-tests-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    let cache = XNewsFeedCache(url: temporaryURL)
    let validOutput = try grokEnvelope(feedDocuments: [
        feed(topics: [
            topic(category: "AI", headline: "One", handle: "@one", date: referenceNow.addingTimeInterval(-600)),
            topic(category: "Robotics", headline: "Two", handle: "@two", date: referenceNow.addingTimeInterval(-900)),
        ]),
    ])
    let validFeed = try GrokXNewsParser.parse(grokOutput: validOutput, now: referenceNow)
    try cache.save(validFeed)

    let invalidOutput = try grokEnvelope(feedDocuments: [[
        "window": ["since": "bad", "until": "bad"],
        "generated_at": "bad",
        "topics": [],
    ]])
    #expect(throws: GrokXNewsError.self) {
        try GrokXNewsParser.parse(grokOutput: invalidOutput, now: referenceNow)
    }
    #expect(try cache.load(now: referenceNow) == validFeed)
}

@Test func grokToolsRequireExplicitConsentBeforeProcessLaunch() throws {
    let source = GrokXNewsSource(
        cache: XNewsFeedCache(url: URL(fileURLWithPath: "/tmp/not-used-x-news.json")),
        environment: ["ILO_BOARD_GROK_PATH": "/bin/sh"]
    )
    #expect(throws: GrokXNewsError.self) {
        try source.refresh(explicitlyAllowsGrokTools: false, now: referenceNow)
    }
}

@Test func refreshPolicyDefaultsToOneMorningRunAndCanOfferTwoRuns() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 2 * 60 * 60))
    let morning = try #require(ISO8601DateFormatter().date(from: "2026-08-10T06:30:00Z")) // 08:30 local

    let daily = XNewsRefreshPolicy()
    #expect(daily.cadence == .daily)
    #expect(daily.nextAutomaticRefresh(after: morning, calendar: calendar) ==
        ISO8601DateFormatter().date(from: "2026-08-11T06:00:00Z"))

    let twice = XNewsRefreshPolicy(cadence: .morningAndAfternoon)
    #expect(twice.nextAutomaticRefresh(after: morning, calendar: calendar) ==
        ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z"))
}

@Test func manualRefreshHasAShortCostSafetyCooldown() {
    let policy = XNewsRefreshPolicy()
    #expect(policy.allowsManualRefresh(lastAttempt: nil, now: referenceNow))
    #expect(!policy.allowsManualRefresh(lastAttempt: referenceNow.addingTimeInterval(-899), now: referenceNow))
    #expect(policy.allowsManualRefresh(lastAttempt: referenceNow.addingTimeInterval(-900), now: referenceNow))
}

@Test func refreshOptInSettingsRoundTripAndDefaultOff() throws {
    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-x-news-settings-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    let store = XNewsRefreshSettingsStore(url: temporaryURL)
    #expect(store.load().cadence == .off)

    let attempt = referenceNow.addingTimeInterval(-300)
    let settings = XNewsRefreshSettings(cadence: .morningAndAfternoon, lastAttemptAt: attempt)
    try store.save(settings)

    #expect(store.load() == settings)
}

private func topic(
    category: String,
    headline: String,
    handle: String,
    date: Date,
    includeSource: Bool = true
) -> [String: Any] {
    let bareHandle = String(handle.dropFirst())
    return [
        "category": category,
        "headline": headline,
        "summary": "A bounded synthetic summary used only by the validator test.",
        "confidence": "high",
        "posted_at": ISO8601DateFormatter().string(from: date),
        "sources": includeSource ? [[
            "handle": handle,
            "post_url": "https://x.com/\(bareHandle)/status/\(snowflakeID(for: date))",
        ]] : [],
    ]
}

private func feed(topics: [[String: Any]]) -> [String: Any] {
    [
        "window": [
            "since": "2026-08-09T09:00:00Z",
            "until": "2026-08-10T09:00:00Z",
        ],
        "generated_at": "2026-08-10T09:00:00Z",
        "topics": topics,
    ]
}

private func grokEnvelope(feedDocuments: [[String: Any]]) throws -> Data {
    let text = try feedDocuments.map { document in
        String(decoding: try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]), as: UTF8.self)
    }.joined()
    return try JSONSerialization.data(withJSONObject: [
        "text": text,
        "sessionId": "ignored",
        "thought": "ignored",
        "usage": ["cost": 123],
    ], options: [.sortedKeys])
}

private func snowflakeID(for date: Date) -> String {
    let milliseconds = UInt64(date.timeIntervalSince1970 * 1_000)
    return String((milliseconds - 1_288_834_974_657) << 22)
}
