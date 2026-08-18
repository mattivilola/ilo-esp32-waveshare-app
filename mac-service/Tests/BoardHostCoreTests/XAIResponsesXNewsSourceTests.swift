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

@Test func responsesAPIRequiresXSearchAllowsThreeParallelTurnsAndCachesValidatedFeed() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-xai-responses-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let transport = CapturingXAITransport(response: XAIHTTPResponse(
        data: try responsesEnvelope(includeSearchCall: true, costTicks: 123_400_000),
        statusCode: 200
    ))
    let source = XAIResponsesXNewsSource(
        cache: XNewsFeedCache(url: cacheURL),
        apiKeyProvider: StaticXAIKeyProvider(),
        transport: transport,
        endpoint: URL(string: "https://api.x.ai/v1/responses")!
    )

    let result = try await source.refresh(now: apiReferenceNow)

    #expect(result.feed.stories.count == 2)
    #expect(result.costInUSDTicks == 123_400_000)
    #expect(try XNewsFeedCache(url: cacheURL).load(now: apiReferenceNow).stories.count == 2)
    let request = try #require(await transport.capturedRequest())
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xai-test-key-that-is-never-persisted")
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["store"] as? Bool == false)
    #expect(json["tool_choice"] as? String == "required")
    #expect(json["parallel_tool_calls"] as? Bool == true)
    #expect(json["max_turns"] as? Int == 3)
    let reasoning = try #require(json["reasoning"] as? [String: Any])
    #expect(reasoning["effort"] as? String == "low")
    let tools = try #require(json["tools"] as? [[String: Any]])
    #expect(tools.count == 1)
    #expect(tools[0]["type"] as? String == "x_search")
    #expect(json["text"] == nil)
    let input = try #require(json["input"] as? String)
    #expect(input.contains("at most two parallel searches total"))
    #expect(input.contains("The one JSON object must conform exactly to this schema:"))
    #expect(input.contains(GrokXNewsContract.jsonSchema))
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
        #expect(error.diagnostic == "status=incomplete; output=x_search_call:completed,message")
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
    #expect(settingsStore.load().lastCostInUSDTicks == 77_000_000)
    let failure = try #require(await coordinator.failureDescription())
    #expect(failure.contains("xAI returned an unusable X News brief: expected 2 to 15 stories"))
    #expect(failure.contains("status=completed; output=x_search_call:completed,message"))
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
        #expect(error.diagnostic == "status=completed; output=message")
    }
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
    feedText: String? = nil
) throws -> Data {
    var output = [[String: Any]]()
    if includeSearchCall {
        output.append(["type": "x_search_call", "status": "completed"])
    }
    output.append([
        "type": "message",
        "content": [["type": "output_text", "text": try feedText ?? directFeedText()]],
    ])
    var root: [String: Any] = ["status": status, "output": output]
    if let costTicks {
        root["usage"] = ["cost_in_usd_ticks": costTicks]
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

private func xSnowflakeID(for date: Date) -> UInt64 {
    let milliseconds = UInt64(date.timeIntervalSince1970 * 1000)
    return (milliseconds - 1_288_834_974_657) << 22
}
