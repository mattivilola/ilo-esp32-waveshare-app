import BoardProtocol
import Foundation

public enum CodexSourceError: Error, LocalizedError, Sendable {
    case executableNotFound
    case requestAlreadyRunning
    case processFailed(String)
    case requestTimedOut
    case invalidResponse
    case rpcError(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Codex CLI was not found. Install/authenticate Codex or set ILO_BOARD_CODEX_PATH."
        case .requestAlreadyRunning:
            "A Codex status request is already running."
        case let .processFailed(message):
            "Codex App Server failed: \(message)"
        case .requestTimedOut:
            "Codex App Server did not answer within five seconds."
        case .invalidResponse:
            "Codex App Server returned an invalid thread list."
        case let .rpcError(message):
            "Codex App Server error: \(message)"
        }
    }
}

public enum CodexExecutableResolver {
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidates = [String]()
        if let configured = environment["ILO_BOARD_CODEX_PATH"], !configured.isEmpty {
            candidates.append(configured)
        }
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }
        candidates.append(contentsOf: ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"])
        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}

struct CodexThreadRecord: Decodable, Equatable, Sendable {
    let id: String
    let name: String?
    let updatedAt: Int64
    let status: CodexThreadStatus
}

struct CodexThreadStatus: Decodable, Equatable, Sendable {
    let type: String
    let activeFlags: [String]?
}

private struct ThreadListResult: Decodable, Sendable {
    let data: [CodexThreadRecord]
}

private struct RPCErrorBody: Decodable, Sendable {
    let message: String
}

private struct ThreadListEnvelope: Decodable, Sendable {
    let id: Int?
    let result: ThreadListResult?
    let error: RPCErrorBody?
}

actor CodexAppServerClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var pendingID: Int?
    private var pending: CheckedContinuation<[CodexThreadRecord], Error>?
    private var timeoutTask: Task<Void, Never>?
    private var nextID = 2

    func listThreads(limit: Int) async throws -> [CodexThreadRecord] {
        guard pending == nil else { throw CodexSourceError.requestAlreadyRunning }
        guard let executable = CodexExecutableResolver.resolve() else {
            throw CodexSourceError.executableNotFound
        }
        try start(executable: executable)
        let requestID = nextID
        nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pendingID = requestID
            pending = continuation
            do {
                try send([
                    "id": requestID,
                    "method": "thread/list",
                    "params": [
                        "limit": max(1, min(limit, 12)),
                        "archived": false,
                        "sortKey": "updated_at",
                        "sortDirection": "desc",
                        "useStateDbOnly": true,
                    ] as [String: Any],
                ])
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    await self?.timeout(requestID: requestID)
                }
            } catch {
                finish(.failure(error))
            }
        }
    }

    private func start(executable: URL) throws {
        shutdown()
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            guard process.terminationStatus != 15 else { return }
            Task { await self?.terminated(status: process.terminationStatus) }
        }
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.receive(data) }
        }
        self.process = process
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        buffer.removeAll(keepingCapacity: true)
        do {
            try process.run()
            try send([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "ilo-board-host",
                        "title": "ILO Board Host",
                        "version": "0.1.0",
                    ],
                    "capabilities": ["experimentalApi": true],
                ],
            ])
            try send(["method": "initialized"])
        } catch {
            shutdown()
            throw CodexSourceError.processFailed(error.localizedDescription)
        }
    }

    private func send(_ object: [String: Any]) throws {
        guard let input else { throw CodexSourceError.processFailed("stdin is unavailable") }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let envelope = try? JSONDecoder().decode(ThreadListEnvelope.self, from: line),
                  envelope.id == pendingID
            else {
                continue
            }
            if let error = envelope.error {
                finish(.failure(CodexSourceError.rpcError(error.message)))
            } else if let result = envelope.result {
                finish(.success(result.data))
            } else {
                finish(.failure(CodexSourceError.invalidResponse))
            }
        }
    }

    private func timeout(requestID: Int) {
        guard pendingID == requestID else { return }
        finish(.failure(CodexSourceError.requestTimedOut))
    }

    private func terminated(status: Int32) {
        guard pending != nil else { return }
        finish(.failure(CodexSourceError.processFailed("exit status \(status)")))
    }

    private func finish(_ result: Result<[CodexThreadRecord], Error>) {
        let continuation = pending
        pending = nil
        pendingID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        shutdown()
        continuation?.resume(with: result)
    }

    private func shutdown() {
        output?.readabilityHandler = nil
        try? input?.close()
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        input = nil
        output = nil
        buffer.removeAll(keepingCapacity: true)
    }
}

enum CodexHistoryMapper {
    static func task(from thread: CodexThreadRecord) -> TaskCard {
        let title = thread.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title?.isEmpty == false ? title! : "Untitled Codex task"
        let flags = Set(thread.status.activeFlags ?? [])
        let state: TaskState
        let attention: AttentionKind
        let summary: String
        switch thread.status.type {
        case "active" where flags.contains("waitingOnApproval"):
            state = .waiting
            attention = .approval
            summary = "Approval requested in local Codex"
        case "active" where flags.contains("waitingOnUserInput"):
            state = .waiting
            attention = .question
            summary = "Answer requested in local Codex"
        case "active":
            state = .active
            attention = .none
            summary = "Working in local Codex"
        case "systemError":
            state = .failed
            attention = .none
            summary = "Local Codex task reported an error"
        case "idle":
            state = .idle
            attention = .none
            summary = "Idle in local Codex"
        case "notLoaded":
            state = .idle
            attention = .none
            summary = "Recent history · live Desktop status unavailable"
        default:
            state = .idle
            attention = .none
            summary = "Recent Codex history"
        }
        return TaskCard(
            id: thread.id,
            title: safeTitle,
            state: state,
            attentionKind: attention,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(thread.updatedAt)),
            shortSummary: summary
        )
    }
}

public actor CodexHistoryTaskSource: TaskSource {
    private let client = CodexAppServerClient()
    private var cachedAt = Date.distantPast
    private var cachedThreads = [CodexThreadRecord]()

    public init() {}

    public func snapshot(revision: UInt64) async throws -> DashboardSnapshot {
        let now = Date()
        let threads: [CodexThreadRecord]
        if now.timeIntervalSince(cachedAt) < 15, !cachedThreads.isEmpty {
            threads = cachedThreads
        } else {
            threads = try await client.listThreads(limit: 6)
            cachedThreads = threads
            cachedAt = now
        }
        return DashboardSnapshot(
            revision: revision,
            generatedAt: now,
            tasks: threads.prefix(6).map(CodexHistoryMapper.task)
        )
    }
}
