import Foundation

public enum XAIResponsesError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidAPIKey
    case insufficientCredits
    case rateLimited
    case requestRejected
    case serviceUnavailable
    case networkFailure
    case timedOut
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add an xAI API key in the Mac companion first."
        case .invalidAPIKey:
            "xAI rejected the API key. Replace it in the Mac companion."
        case .insufficientCredits:
            "xAI API credits are unavailable. Check API billing in the xAI Console."
        case .rateLimited:
            "xAI rate-limited the request. Try again shortly."
        case .requestRejected:
            "xAI rejected the X News request."
        case .serviceUnavailable:
            "The xAI API is temporarily unavailable."
        case .networkFailure:
            "The Mac could not reach the xAI API."
        case .timedOut:
            "xAI did not finish the X News search within ten minutes. Try again later."
        case .malformedResponse:
            "xAI returned an unreadable X News response."
        }
    }
}

public struct XAIResponseRejectedError: Error, LocalizedError, Sendable {
    public let message: String
    public let diagnostic: String
    public let costInUSDTicks: Int64?

    public init(message: String, diagnostic: String, costInUSDTicks: Int64?) {
        self.message = String(message.prefix(160))
        self.diagnostic = String(diagnostic.prefix(160))
        self.costInUSDTicks = costInUSDTicks
    }

    public var errorDescription: String? {
        "\(message) · \(diagnostic)"
    }
}

public struct XNewsFetchResult: Sendable {
    public let feed: XNewsFeed
    public let costInUSDTicks: Int64?

    public init(feed: XNewsFeed, costInUSDTicks: Int64?) {
        self.feed = feed
        self.costInUSDTicks = costInUSDTicks
    }
}

public protocol XNewsFeedRefreshing: Sendable {
    func refresh(now: Date) async throws -> XNewsFetchResult
}

public struct XAIHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol XAIHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> XAIHTTPResponse
}

public struct URLSessionXAIHTTPTransport: XAIHTTPTransport, Sendable {
    public static let timeout: TimeInterval = 10 * 60
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> XAIHTTPResponse {
        let taskBox = URLSessionTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let response = response as? HTTPURLResponse else {
                        continuation.resume(throwing: XAIResponsesError.malformedResponse)
                        return
                    }
                    continuation.resume(returning: XAIHTTPResponse(data: data, statusCode: response.statusCode))
                }
                taskBox.store(task)
                task.resume()
            }
        } onCancel: {
            taskBox.cancel()
        }
    }
}

private final class URLSessionTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false

    func store(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

public struct XAIResponsesXNewsSource: XNewsFeedRefreshing, Sendable {
    public static let defaultEndpoint = URL(string: "https://api.x.ai/v1/responses")!
    public static let model = "grok-4.5"

    private let cache: XNewsFeedCache
    private let apiKeyProvider: any XAIAPIKeyProviding
    private let transport: any XAIHTTPTransport
    private let endpoint: URL
    private let hardDeadline: Duration

    public init(
        cache: XNewsFeedCache = XNewsFeedCache(),
        apiKeyProvider: any XAIAPIKeyProviding = XAIAPIKeyStore(),
        transport: any XAIHTTPTransport = URLSessionXAIHTTPTransport(),
        endpoint: URL = Self.defaultEndpoint,
        hardDeadline: Duration = .seconds(URLSessionXAIHTTPTransport.timeout)
    ) {
        self.cache = cache
        self.apiKeyProvider = apiKeyProvider
        self.transport = transport
        self.endpoint = endpoint
        self.hardDeadline = hardDeadline
    }

    public func refresh(now: Date = Date()) async throws -> XNewsFetchResult {
        let apiKey: String
        do {
            apiKey = try apiKeyProvider.loadAPIKey()
        } catch XAIAPIKeyError.notFound {
            throw XAIResponsesError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = URLSessionXAIHTTPTransport.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try requestBody(now: now)

        let response: XAIHTTPResponse
        do {
            response = try await sendWithHardDeadline(request)
        } catch let error as XAIResponsesError {
            throw error
        } catch {
            throw XAIResponsesError.networkFailure
        }
        try Self.validate(statusCode: response.statusCode, data: response.data)
        guard response.data.count <= 1_000_000 else {
            throw GrokXNewsError.invalidFeed("response exceeds the one-megabyte safety limit")
        }

        let envelope: ResponsesEnvelope
        do {
            envelope = try JSONDecoder().decode(ResponsesEnvelope.self, from: response.data)
        } catch {
            throw XAIResponsesError.malformedResponse
        }
        let diagnostic = Self.diagnosticSummary(envelope)
        guard envelope.status == "completed" else {
            throw XAIResponseRejectedError(
                message: "xAI stopped before writing the X News brief. No cache was changed.",
                diagnostic: diagnostic,
                costInUSDTicks: envelope.usage?.costInUSDTicks
            )
        }
        guard envelope.output.contains(where: { $0.type == "x_search_call" && $0.status == "completed" }) else {
            throw XAIResponseRejectedError(
                message: "xAI returned no completed X search. No cache was changed.",
                diagnostic: diagnostic,
                costInUSDTicks: envelope.usage?.costInUSDTicks
            )
        }
        guard let text = envelope.output
            .first(where: { $0.type == "message" })?
            .content?
            .first(where: { $0.type == "output_text" })?
            .text
        else {
            throw XAIResponseRejectedError(
                message: "xAI searched X but did not write the final brief. No cache was changed.",
                diagnostic: diagnostic,
                costInUSDTicks: envelope.usage?.costInUSDTicks
            )
        }

        let candidate: XNewsFeed
        do {
            candidate = try GrokXNewsParser.parse(feedText: text, now: now)
        } catch {
            throw XAIResponseRejectedError(
                message: Self.rejectedBriefMessage(error),
                diagnostic: diagnostic,
                costInUSDTicks: envelope.usage?.costInUSDTicks
            )
        }
        let feed = try XNewsRollingFeedMerger.merge(
            candidate: candidate,
            previous: try? cache.loadIncludingStale(),
            now: now
        )
        try cache.save(feed)
        return XNewsFetchResult(feed: feed, costInUSDTicks: envelope.usage?.costInUSDTicks)
    }

    private func requestBody(now: Date) throws -> Data {
        let since = now.addingTimeInterval(-GrokXNewsContract.maximumAge)
        let body: [String: Any] = [
            "model": Self.model,
            "input": GrokXNewsContract.prompt(now: now),
            "tools": [[
                "type": "x_search",
                "from_date": Self.dayString(since),
                "to_date": Self.dayString(now),
            ]],
            "tool_choice": "auto",
            "parallel_tool_calls": true,
            "max_turns": 3,
            "max_output_tokens": 12_000,
            "reasoning": ["effort": "low"],
            "store": false,
            "include": ["no_inline_citations"],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    private func sendWithHardDeadline(_ request: URLRequest) async throws -> XAIHTTPResponse {
        let transport = self.transport
        let hardDeadline = self.hardDeadline
        return try await withCheckedThrowingContinuation { continuation in
            let race = XAIHTTPResponseRace(continuation: continuation)
            let responseTask = Task {
                do {
                    race.finish(.success(try await transport.send(request)))
                } catch {
                    race.finish(.failure(error))
                }
            }
            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: hardDeadline)
                    race.finish(.failure(XAIResponsesError.timedOut))
                } catch {
                    // The response won the race and cancelled this timer.
                }
            }
            race.install(responseTask: responseTask, timeoutTask: timeoutTask)
        }
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func diagnosticSummary(_ envelope: ResponsesEnvelope) -> String {
        let status = diagnosticToken(envelope.status)
        let items = envelope.output.prefix(8).map { item in
            let type = diagnosticToken(item.type)
            guard let itemStatus = item.status else { return type }
            return "\(type):\(diagnosticToken(itemStatus))"
        }
        let output = items.isEmpty ? "none" : items.joined(separator: ",")
        return "status=\(status); output=\(output)"
    }

    private static func diagnosticToken(_ value: String) -> String {
        let allowed = value.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
        let token = String(String.UnicodeScalarView(allowed)).prefix(32)
        return token.isEmpty ? "unknown" : String(token)
    }

    private static func rejectedBriefMessage(_ error: Error) -> String {
        switch error as? GrokXNewsError {
        case let .invalidFeed(reason):
            "xAI returned an unusable X News brief: \(reason). No cache was changed."
        case .malformedFeed, .malformedEnvelope:
            "xAI returned no readable structured X News brief. No cache was changed."
        default:
            "xAI returned an unusable X News brief. No cache was changed."
        }
    }

    private static func validate(statusCode: Int, data: Data) throws {
        guard !(200..<300).contains(statusCode) else { return }
        switch statusCode {
        case 401, 403:
            throw XAIResponsesError.invalidAPIKey
        case 402:
            throw XAIResponsesError.insufficientCredits
        case 429:
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?
                .error.message.lowercased() ?? ""
            if message.contains("credit") || message.contains("billing") || message.contains("spend") {
                throw XAIResponsesError.insufficientCredits
            }
            throw XAIResponsesError.rateLimited
        case 500...599:
            throw XAIResponsesError.serviceUnavailable
        default:
            throw XAIResponsesError.requestRejected
        }
    }
}

private final class XAIHTTPResponseRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<XAIHTTPResponse, any Error>?
    private var responseTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(continuation: CheckedContinuation<XAIHTTPResponse, any Error>) {
        self.continuation = continuation
    }

    func install(responseTask: Task<Void, Never>, timeoutTask: Task<Void, Never>) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            responseTask.cancel()
            timeoutTask.cancel()
            return
        }
        self.responseTask = responseTask
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    func finish(_ result: Result<XAIHTTPResponse, any Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let responseTask = self.responseTask
        let timeoutTask = self.timeoutTask
        self.responseTask = nil
        self.timeoutTask = nil
        lock.unlock()

        responseTask?.cancel()
        timeoutTask?.cancel()
        continuation.resume(with: result)
    }
}

private struct ResponsesEnvelope: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            let type: String
            let text: String?
        }

        let type: String
        let status: String?
        let content: [ContentItem]?
    }

    struct Usage: Decodable {
        let costInUSDTicks: Int64?

        enum CodingKeys: String, CodingKey {
            case costInUSDTicks = "cost_in_usd_ticks"
        }
    }

    let output: [OutputItem]
    let status: String
    let usage: Usage?
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
