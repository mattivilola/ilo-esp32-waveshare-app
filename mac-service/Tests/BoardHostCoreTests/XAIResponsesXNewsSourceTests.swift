@testable import BoardHostCore
import Foundation
import Testing

private let apiReferenceNow = ISO8601DateFormatter().date(from: "2026-08-17T09:00:00Z")!

@Test func xaiAPIKeyValidationAcceptsOnlyBoundedNonWhitespaceKeys() throws {
    let valid = "xai-" + String(repeating: "a", count: 40)
    #expect(try XAIAPIKeyStore.normalized("  \(valid)\n") == valid)
    #expect(throws: XAIAPIKeyError.self) {
        try XAIAPIKeyStore.normalized("not-an-xai-key")
    }
    #expect(throws: XAIAPIKeyError.self) {
        try XAIAPIKeyStore.normalized("xai-key with spaces and enough characters")
    }
}

@Test func responsesAPIRunsTwoBoundedCategorySearchesAndCachesOneMergedFeed() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-xai-responses-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let transport = CategoryCapturingXAITransport(
        aiResponse: XAIHTTPResponse(
            data: try responsesEnvelope(
                includeSearchCall: true,
                costTicks: 100_000_000,
                feedText: try categoryFeedText(.ai),
                searchCallType: "custom_tool_call",
                successfulXSearchCalls: 1
            ),
            statusCode: 200
        ),
        roboticsResponse: XAIHTTPResponse(
            data: try responsesEnvelope(
                includeSearchCall: true,
                costTicks: 23_400_000,
                feedText: try categoryFeedText(.robotics),
                searchCallType: "custom_tool_call",
                successfulXSearchCalls: 1
            ),
            statusCode: 200
        )
    )
    let source = XAIResponsesXNewsSource(
        cache: XNewsFeedCache(url: cacheURL),
        apiKeyProvider: StaticXAIKeyProvider(),
        transport: transport,
        endpoint: URL(string: "https://api.x.ai/v1/responses")!
    )

    let result = try await source.refresh(now: apiReferenceNow)

    #expect(result.feed.stories.count == 10)
    #expect(result.feed.stories.prefix(5).allSatisfy { $0.category == .ai })
    #expect(result.feed.stories.suffix(5).allSatisfy { $0.category == .robotics })
    #expect(result.costInUSDTicks == 123_400_000)
    #expect(try XNewsFeedCache(url: cacheURL).load(now: apiReferenceNow).stories.count == 10)
    let requests = await transport.capturedRequests()
    #expect(requests.count == 2)
    var requestedCategories = Set<String>()
    for request in requests {
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xai-test-key-that-is-never-persisted")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["store"] as? Bool == false)
        #expect(json["tool_choice"] as? String == "auto")
        #expect(json["parallel_tool_calls"] as? Bool == false)
        #expect(json["max_turns"] as? Int == 2)
        #expect(json["max_output_tokens"] as? Int == 6_000)
        let reasoning = try #require(json["reasoning"] as? [String: Any])
        #expect(reasoning["effort"] as? String == "low")
        let tools = try #require(json["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "x_search")
        #expect(json["text"] == nil)
        let input = try #require(json["input"] as? String)
        #expect(input.contains("Use the provided X search tool once"))
        #expect(input.contains("Aim for 5 to 8 unique topics"))
        #expect(input.contains("The one JSON object must conform exactly to this schema:"))
        #expect(input.contains(GrokXNewsContract.jsonSchema))
        if input.contains("Category must be exactly AI") { requestedCategories.insert("AI") }
        if input.contains("Category must be exactly Robotics") { requestedCategories.insert("Robotics") }
    }
    #expect(requestedCategories == Set(["AI", "Robotics"]))
}

@Test func responsesAPIEnforcesAHardDeadline() async throws {
    let source = XAIResponsesXNewsSource(
        cache: XNewsFeedCache(url: URL(fileURLWithPath: "/tmp/not-used-xai-timeout-news.json")),
        apiKeyProvider: StaticXAIKeyProvider(),
        transport: SuspendedXAITransport(),
        hardDeadline: .milliseconds(10)
    )

    await #expect(throws: XAIResponsesError.timedOut) {
        try await source.refresh(now: apiReferenceNow)
    }
}

@Test func responsesAPIReturnsActionableFailureWhenToolLoopDoesNotFinish() async throws {
    let transport = CapturingXAITransport(response: XAIHTTPResponse(
        data: try responsesEnvelope(includeSearchCall: true, costTicks: nil, status: "incomplete"),
        statusCode: 200
    ))
    let source = XAIResponsesXNewsSource(
        cache: XNewsFeedCache(url: URL(fileURLWithPath: "/tmp/not-used-incomplete-xai-news.json")),
        apiKeyProvider: StaticXAIKeyProvider(),
        transport: transport
    )

    do {
        _ = try await source.refresh(now: apiReferenceNow)
        Issue.record("Expected an incomplete-response failure")
    } catch let error as XAIResponseRejectedError {
        #expect(error.localizedDescription.contains("xAI stopped before writing the X News brief"))
        #expect(error.diagnostic.contains("AI:status=incomplete; output=x_search_call:completed,message"))
        #expect(error.diagnostic.contains("Robotics:status=incomplete; output=x_search_call:completed,message"))
    }
}

@Test func rejectedStructuredBriefReportsDiagnosticAndPersistsExactCost() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-xai-rejected-cost-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settingsStore = XNewsRefreshSettingsStore(url: directory.appendingPathComponent("settings.json"))
    try settingsStore.save(XNewsRefreshSettings(cadence: .daily))
    let source = XAIResponsesXNewsSource(
        cache: XNewsFeedCache(url: directory.appendingPathComponent("feed.json")),
        apiKeyProvider: StaticXAIKeyProvider(),
        transport: CapturingXAITransport(response: XAIHTTPResponse(
            data: try responsesEnvelope(
                includeSearchCall: true,
                costTicks: 77_000_000,
                feedText: emptyFeedText()
            ),
            statusCode: 200
        ))
    )
    let coordinator = XNewsRefreshCoordinator(
        settingsStore: settingsStore,
        cache: XNewsFeedCache(url: directory.appendingPathComponent("feed.json")),
        source: source
    )

    #expect(await coordinator.requestManualRefresh(now: apiReferenceNow) == .failed)
    #expect(settingsStore.load().lastCostInUSDTicks == 154_000_000)
    let failure = try #require(await coordinator.failureDescription())
    #expect(failure.contains("xAI returned fewer than two usable X News posts across both searches"))
    #expect(failure.contains("AI:status=completed; output=x_search_call:completed,message"))
    #expect(failure.contains("Robotics:status=completed; output=x_search_call:completed,message"))
}

@Test func responsesAPIRejectsOutputWhenXSearchWasNotPerformed() async throws {
    let transport = CapturingXAITransport(response: XAIHTTPResponse(
        data: try responsesEnvelope(includeSearchCall: false, costTicks: nil),
        statusCode: 200
    ))
    let source = XAIResponsesXNewsSource(
        cache: XNewsFeedCache(url: URL(fileURLWithPath: "/tmp/not-used-xai-news.json")),
        apiKeyProvider: StaticXAIKeyProvider(),
        transport: transport
    )

    do {
        _ = try await source.refresh(now: apiReferenceNow)
        Issue.record("Expected a missing-search rejection")
    } catch let error as XAIResponseRejectedError {
        #expect(error.message.contains("no completed X search"))
        #expect(error.diagnostic.contains("AI:status=completed; output=message"))
        #expect(error.diagnostic.contains("Robotics:status=completed; output=message"))
    }
}

@Test func oneRejectedCategoryLeavesTheExistingCacheUntouchedAndReportsBothCosts() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-xai-partial-rejection-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let cache = XNewsFeedCache(url: cacheURL)
    let previous = try GrokXNewsParser.parse(feedText: directFeedText(), now: apiReferenceNow)
    try cache.save(previous)
    let source = XAIResponsesXNewsSource(
        cache: cache,
        apiKeyProvider: StaticXAIKeyProvider(),
        transport: CategoryCapturingXAITransport(
            aiResponse: XAIHTTPResponse(
                data: try responsesEnvelope(
                    includeSearchCall: true,
                    costTicks: 11_000_000,
                    feedText: try categoryFeedText(.ai)
                ),
                statusCode: 200
            ),
            roboticsResponse: XAIHTTPResponse(
                data: try responsesEnvelope(
                    includeSearchCall: false,
                    costTicks: 22_000_000,
                    feedText: emptyFeedText()
                ),
                statusCode: 200
            )
        )
    )

    do {
        _ = try await source.refresh(now: apiReferenceNow)
        Issue.record("Expected the Robotics category to be rejected")
    } catch let error as XAIResponseRejectedError {
        #expect(error.message.contains("Robotics"))
        #expect(error.costInUSDTicks == 33_000_000)
    }
    #expect(try cache.load(now: apiReferenceNow) == previous)
}

@Test func oneExplicitlyEmptyCategoryStillCachesTheOtherCategory() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-xai-empty-category-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let source = XAIResponsesXNewsSource(
        cache: XNewsFeedCache(url: cacheURL),
        apiKeyProvider: StaticXAIKeyProvider(),
        transport: CategoryCapturingXAITransport(
            aiResponse: XAIHTTPResponse(
                data: try responsesEnvelope(
                    includeSearchCall: true,
                    costTicks: 11_000_000,
                    feedText: try categoryFeedText(.ai)
                ),
                statusCode: 200
            ),
            roboticsResponse: XAIHTTPResponse(
                data: try responsesEnvelope(
                    includeSearchCall: true,
                    costTicks: 22_000_000,
                    feedText: emptyFeedText()
                ),
                statusCode: 200
            )
        )
    )

    let result = try await source.refresh(now: apiReferenceNow)

    #expect(result.feed.stories.count == 5)
    #expect(result.feed.stories.allSatisfy { $0.category == .ai })
    #expect(result.costInUSDTicks == 33_000_000)
    #expect(try XNewsFeedCache(url: cacheURL).load(now: apiReferenceNow).stories.count == 5)
}

@Test func twoExplicitlyEmptyCategoriesDoNotCreateAnEmptyCache() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-xai-all-empty-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let emptyResponse = XAIHTTPResponse(
        data: try responsesEnvelope(includeSearchCall: true, costTicks: 22_000_000, feedText: emptyFeedText()),
        statusCode: 200
    )
    let source = XAIResponsesXNewsSource(
        cache: XNewsFeedCache(url: cacheURL),
        apiKeyProvider: StaticXAIKeyProvider(),
        transport: CategoryCapturingXAITransport(aiResponse: emptyResponse, roboticsResponse: emptyResponse)
    )

    do {
        _ = try await source.refresh(now: apiReferenceNow)
        Issue.record("Expected an all-empty refresh to be rejected")
    } catch let error as XAIResponseRejectedError {
        #expect(error.message.contains("fewer than two usable"))
        #expect(error.costInUSDTicks == 44_000_000)
    }
    #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
}

@Test func responsesAPIReturnsActionableAuthenticationFailure() async throws {
    let error = try JSONSerialization.data(withJSONObject: [
        "error": ["message": "Invalid API key"],
    ])
    let source = XAIResponsesXNewsSource(
        cache: XNewsFeedCache(url: URL(fileURLWithPath: "/tmp/not-used-xai-news.json")),
        apiKeyProvider: StaticXAIKeyProvider(),
        transport: CapturingXAITransport(response: XAIHTTPResponse(data: error, statusCode: 401))
    )

    await #expect(throws: XAIResponsesError.self) {
        try await source.refresh(now: apiReferenceNow)
    }
}

@Test func successfulRefreshPersistsExactCostForCompanionDisplay() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-xai-cost-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settingsStore = XNewsRefreshSettingsStore(url: directory.appendingPathComponent("settings.json"))
    try settingsStore.save(XNewsRefreshSettings(cadence: .daily))
    let feed = try GrokXNewsParser.parse(feedText: try directFeedText(), now: apiReferenceNow)
    let coordinator = XNewsRefreshCoordinator(
        settingsStore: settingsStore,
        cache: XNewsFeedCache(url: directory.appendingPathComponent("feed.json")),
        source: StaticXNewsSource(result: XNewsFetchResult(feed: feed, costInUSDTicks: 99_000_000))
    )

    #expect(await coordinator.requestManualRefresh(now: apiReferenceNow) == .updated)
    let settings = settingsStore.load()
    #expect(settings.lastAttemptAt == apiReferenceNow)
    #expect(settings.lastCostInUSDTicks == 99_000_000)
    #expect(await coordinator.failureDescription() == nil)
}

@Test func completedRefreshDoesNotRestoreScheduleDisabledWhileRequestWasRunning() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-xai-disable-race-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settingsStore = XNewsRefreshSettingsStore(url: directory.appendingPathComponent("settings.json"))
    try settingsStore.save(XNewsRefreshSettings(cadence: .daily))
    let feed = try GrokXNewsParser.parse(feedText: try directFeedText(), now: apiReferenceNow)
    let source = SuspendedXNewsSource(result: XNewsFetchResult(feed: feed, costInUSDTicks: 42_000_000))
    let coordinator = XNewsRefreshCoordinator(
        settingsStore: settingsStore,
        cache: XNewsFeedCache(url: directory.appendingPathComponent("feed.json")),
        source: source
    )

    let refresh = Task { await coordinator.requestManualRefresh(now: apiReferenceNow) }
    await source.waitUntilStarted()
    try XNewsFeatureController(settingsStore: settingsStore, apiKeyConfigured: true).disable()
    await source.resume()

    #expect(await refresh.value == .updated)
    #expect(settingsStore.load().cadence == .off)
    #expect(settingsStore.load().lastCostInUSDTicks == 42_000_000)
}

private struct StaticXAIKeyProvider: XAIAPIKeyProviding {
    func loadAPIKey() throws -> String {
        "xai-test-key-that-is-never-persisted"
    }
}

private actor CapturingXAITransport: XAIHTTPTransport {
    private let response: XAIHTTPResponse
    private var request: URLRequest?

    init(response: XAIHTTPResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> XAIHTTPResponse {
        self.request = request
        return response
    }

    func capturedRequest() -> URLRequest? {
        request
    }
}

private actor CategoryCapturingXAITransport: XAIHTTPTransport {
    private let aiResponse: XAIHTTPResponse
    private let roboticsResponse: XAIHTTPResponse
    private var requests = [URLRequest]()

    init(aiResponse: XAIHTTPResponse, roboticsResponse: XAIHTTPResponse) {
        self.aiResponse = aiResponse
        self.roboticsResponse = roboticsResponse
    }

    func send(_ request: URLRequest) async throws -> XAIHTTPResponse {
        requests.append(request)
        guard let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let input = json["input"] as? String
        else {
            throw XAIResponsesError.malformedResponse
        }
        return input.contains("Category must be exactly AI") ? aiResponse : roboticsResponse
    }

    func capturedRequests() -> [URLRequest] {
        requests
    }
}

private struct SuspendedXAITransport: XAIHTTPTransport {
    func send(_: URLRequest) async throws -> XAIHTTPResponse {
        try await Task.sleep(for: .seconds(60))
        throw XAIResponsesError.networkFailure
    }
}

private actor SuspendedXNewsSource: XNewsFeedRefreshing {
    private let result: XNewsFetchResult
    private var started = false
    private var startWaiters = [CheckedContinuation<Void, Never>]()
    private var refreshContinuation: CheckedContinuation<Void, Never>?

    init(result: XNewsFetchResult) {
        self.result = result
    }

    func refresh(now _: Date) async throws -> XNewsFetchResult {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            refreshContinuation = continuation
        }
        return result
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        refreshContinuation?.resume()
        refreshContinuation = nil
    }
}

private struct StaticXNewsSource: XNewsFeedRefreshing {
    let result: XNewsFetchResult

    func refresh(now: Date) async throws -> XNewsFetchResult {
        result
    }
}

private func responsesEnvelope(
    includeSearchCall: Bool,
    costTicks: Int64?,
    status: String = "completed",
    feedText: String? = nil,
    searchCallType: String = "x_search_call",
    successfulXSearchCalls: Int? = nil
) throws -> Data {
    var output = [[String: Any]]()
    if includeSearchCall {
        output.append(["type": searchCallType, "status": "completed"])
    }
    output.append([
        "type": "message",
        "content": [["type": "output_text", "text": try feedText ?? directFeedText()]],
    ])
    var root: [String: Any] = ["status": status, "output": output]
    var usage = [String: Any]()
    if let costTicks {
        usage["cost_in_usd_ticks"] = costTicks
    }
    if let successfulXSearchCalls {
        usage["server_side_tool_usage_details"] = ["x_search_calls": successfulXSearchCalls]
    }
    if !usage.isEmpty {
        root["usage"] = usage
    }
    return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
}

private func emptyFeedText() -> String {
    """
    {
      "window": {"since": "2026-08-16T09:00:00Z", "until": "2026-08-17T09:00:00Z"},
      "generated_at": "2026-08-17T09:00:00Z",
      "topics": []
    }
    """
}

private func directFeedText() throws -> String {
    let dates = [
        apiReferenceNow.addingTimeInterval(-600),
        apiReferenceNow.addingTimeInterval(-900),
    ]
    let topics = dates.enumerated().map { index, date in
        let handle = index == 0 ? "source_ai" : "source_robot"
        return [
            "category": index == 0 ? "AI" : "Robotics",
            "headline": index == 0 ? "New AI development" : "New robotics development",
            "summary": "A bounded direct X development returned by the API contract test.",
            "post_text": "Complete direct post text returned for the board detail reader.",
            "confidence": "high",
            "posted_at": ISO8601DateFormatter().string(from: date),
            "sources": [[
                "handle": "@\(handle)",
                "post_url": "https://x.com/\(handle)/status/\(xSnowflakeID(for: date))",
            ]],
        ] as [String: Any]
    }
    let feed: [String: Any] = [
        "window": [
            "since": "2026-08-16T09:00:00Z",
            "until": "2026-08-17T09:00:00Z",
        ],
        "generated_at": "2026-08-17T09:00:00Z",
        "topics": topics,
    ]
    let data = try JSONSerialization.data(withJSONObject: feed, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func categoryFeedText(_ category: XNewsCategory) throws -> String {
    let baseOffset = category == .ai ? 0 : 1_800
    let topics = (0..<5).map { index in
        let date = apiReferenceNow.addingTimeInterval(TimeInterval(-600 - baseOffset - index * 60))
        let handle = category == .ai ? "ai_\(index)" : "robot_\(index)"
        return [
            "category": category.rawValue,
            "headline": "\(category.rawValue) development \(index)",
            "summary": "A bounded direct X development returned by the category API contract test.",
            "post_text": "Complete direct post text returned for the board detail reader.",
            "confidence": index.isMultiple(of: 2) ? "high" : "medium",
            "posted_at": ISO8601DateFormatter().string(from: date),
            "sources": [[
                "handle": "@\(handle)",
                "post_url": "https://x.com/\(handle)/status/\(xSnowflakeID(for: date))",
            ]],
        ] as [String: Any]
    }
    let feed: [String: Any] = [
        "window": [
            "since": "2026-08-16T09:00:00Z",
            "until": "2026-08-17T09:00:00Z",
        ],
        "generated_at": "2026-08-17T09:00:00Z",
        "topics": topics,
    ]
    let data = try JSONSerialization.data(withJSONObject: feed, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func xSnowflakeID(for date: Date) -> UInt64 {
    let milliseconds = UInt64(date.timeIntervalSince1970 * 1000)
    return (milliseconds - 1_288_834_974_657) << 22
}
