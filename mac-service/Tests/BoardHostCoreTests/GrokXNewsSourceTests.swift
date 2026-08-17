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

@Test func directXNewsFeedCanCarryFifteenStoriesWithReadablePostText() throws {
    let topics = (0..<15).map { index in
        topic(
            category: index.isMultiple(of: 2) ? "AI" : "Robotics",
            headline: "Direct development \(index)",
            handle: "@source\(index)",
            date: referenceNow.addingTimeInterval(TimeInterval(-600 - index * 60))
        )
    }
    let parsed = try GrokXNewsParser.parse(
        grokOutput: grokEnvelope(feedDocuments: [feed(topics: topics)]),
        now: referenceNow
    )

    #expect(GrokXNewsContract.maximumStories == 15)
    #expect(parsed.stories.count == 15)
    let wire = XNewsWireMapper.snapshot(from: parsed)
    #expect(wire.stories.count == 15)
    #expect(wire.stories[0].postText == "Complete synthetic X post text for the detail reader.")
}

@Test func rollingFeedRetainsCurrentLastGoodStoriesAndDropsResearchNotes() throws {
    let previous = XNewsFeed(
        generatedAt: referenceNow.addingTimeInterval(-3_600),
        stories: (0..<5).map { index in
            testStory(
                title: index == 4 ? "Need more robotics primaries" : "Previous \(index)",
                handle: "@previous\(index)",
                date: referenceNow.addingTimeInterval(TimeInterval(-3_600 - index * 60))
            )
        }
    )
    let candidate = XNewsFeed(
        generatedAt: referenceNow,
        stories: (0..<2).map { index in
            testStory(
                title: "New \(index)",
                handle: "@new\(index)",
                date: referenceNow.addingTimeInterval(TimeInterval(-600 - index * 60))
            )
        }
    )

    let merged = try XNewsRollingFeedMerger.merge(candidate: candidate, previous: previous, now: referenceNow)
    #expect(merged.stories.count == 6)
    #expect(merged.stories.prefix(2).map(\.title) == ["New 0", "New 1"])
    #expect(!merged.stories.contains { $0.title.contains("Need more") })
}

@Test func researchProgressCannotBecomeABoardNewsStory() throws {
    let output = try grokEnvelope(feedDocuments: [
        feed(topics: [
            topic(
                category: "AI",
                headline: "Remaining work is more AI primaries",
                handle: "@notes",
                date: referenceNow.addingTimeInterval(-600)
            ),
            topic(
                category: "Robotics",
                headline: "Real verified robotics launch",
                handle: "@robot",
                date: referenceNow.addingTimeInterval(-900)
            ),
        ]),
    ])
    #expect(throws: GrokXNewsError.self) {
        try GrokXNewsParser.parse(grokOutput: output, now: referenceNow)
    }
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

@Test func staleStoryIsDroppedWhenTwoFullyVerifiedStoriesRemain() throws {
    let mixed = feed(topics: [
        topic(category: "AI", headline: "Old item", handle: "@old", date: referenceNow.addingTimeInterval(-86_401)),
        topic(category: "AI", headline: "Fresh AI item", handle: "@fresh_ai", date: referenceNow.addingTimeInterval(-600)),
        topic(category: "Robotics", headline: "Fresh robotics item", handle: "@fresh_bot", date: referenceNow.addingTimeInterval(-900)),
    ])

    let parsed = try GrokXNewsParser.parse(
        grokOutput: grokEnvelope(feedDocuments: [mixed]),
        now: referenceNow
    )

    #expect(parsed.stories.map(\.title) == ["Fresh AI item", "Fresh robotics item"])
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

@Test func xNewsFeatureRequiresAPIKeyAndExplicitConsentAndCanBeDisabled() throws {
    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-x-news-feature-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    let store = XNewsRefreshSettingsStore(url: temporaryURL)

    let unavailable = XNewsFeatureController(settingsStore: store, apiKeyConfigured: false)
    #expect(unavailable.status() == XNewsFeatureStatus(cadence: .off, apiKeyConfigured: false))
    #expect(throws: XAIResponsesError.self) {
        try unavailable.enable(cadence: .daily, explicitlyAllowsPaidAPI: true)
    }

    let available = XNewsFeatureController(settingsStore: store, apiKeyConfigured: true)
    #expect(throws: GrokXNewsError.self) {
        try available.enable(cadence: .daily, explicitlyAllowsPaidAPI: false)
    }
    try available.enable(cadence: .morningAndAfternoon, explicitlyAllowsPaidAPI: true)
    #expect(available.status().isEnabled)
    #expect(available.status().cadence == .morningAndAfternoon)

    try available.disable()
    #expect(available.status() == XNewsFeatureStatus(cadence: .off, apiKeyConfigured: true))
}

@Test func legacyGrokConsentCannotSilentlyEnableSeparatelyBilledAPIRefreshes() throws {
    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-x-news-consent-migration-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    let store = XNewsRefreshSettingsStore(url: temporaryURL)
    try store.save(XNewsRefreshSettings(cadence: .daily, consentVersion: 1))
    let controller = XNewsFeatureController(settingsStore: store, apiKeyConfigured: true)

    #expect(controller.status().cadence == .off)
    #expect(!controller.status().isEnabled)

    try controller.enable(cadence: .daily, explicitlyAllowsPaidAPI: true)
    #expect(store.load().consentVersion == XNewsRefreshSettings.currentConsentVersion)
    #expect(controller.status().isEnabled)
}

@Test func boardRefreshRequestRequiresMacConsentAndHonorsCooldown() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-x-news-board-request-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settingsStore = XNewsRefreshSettingsStore(url: directory.appendingPathComponent("settings.json"))
    let cache = XNewsFeedCache(url: directory.appendingPathComponent("feed.json"))
    let coordinator = XNewsRefreshCoordinator(settingsStore: settingsStore, cache: cache)

    #expect(await coordinator.requestManualRefresh(now: referenceNow) == .disabled)
    #expect(await coordinator.activity(now: referenceNow) == .disabled)

    try settingsStore.save(XNewsRefreshSettings(
        cadence: .daily,
        lastAttemptAt: referenceNow.addingTimeInterval(-60)
    ))
    #expect(await coordinator.requestManualRefresh(now: referenceNow) == .cooldown)
    #expect(await coordinator.activity(now: referenceNow) == .cooldown(until: referenceNow.addingTimeInterval(14 * 60)))
    #expect(await coordinator.activity(now: referenceNow.addingTimeInterval(15 * 60)) == .idle)
}

@Test func xNewsWireTextUsesBoardSafeTypographyWithoutChangingTheCacheModel() {
    #expect(XNewsWireMapper.boardSafeText("xAI’s été — next…") == "xAI's ete - next...")
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
        "post_text": "Complete synthetic X post text for the detail reader.",
        "confidence": "high",
        "posted_at": ISO8601DateFormatter().string(from: date),
        "sources": includeSource ? [[
            "handle": handle,
            "post_url": "https://x.com/\(bareHandle)/status/\(snowflakeID(for: date))",
        ]] : [],
    ]
}

private func testStory(title: String, handle: String, date: Date) -> XNewsStory {
    let bareHandle = String(handle.dropFirst())
    return XNewsStory(
        title: title,
        summary: "A finished development for rolling-feed tests.",
        postText: "Complete rolling-feed post text.",
        category: .ai,
        confidence: .high,
        sources: [XNewsCitation(
            handle: handle,
            postedAt: date,
            xURL: URL(string: "https://x.com/\(bareHandle)/status/\(snowflakeID(for: date))")!
        )]
    )
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
