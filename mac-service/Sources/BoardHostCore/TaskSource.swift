import BoardProtocol
import Foundation

public protocol TaskSource: Sendable {
    func snapshot(revision: UInt64) async throws -> DashboardSnapshot
    func continueTask(id: String, requestID: String) async -> CodexContinueOutcome
}

public enum CodexContinueOutcome: Sendable {
    case accepted
    case unavailable
    case busy
    case rejected
    case failed
}

public extension TaskSource {
    func continueTask(id: String, requestID: String) async -> CodexContinueOutcome {
        .unavailable
    }
}

public struct MockTaskSource: TaskSource {
    public init() {}

    public func snapshot(revision: UInt64) async throws -> DashboardSnapshot {
        let now = Date()
        return DashboardSnapshot(
            revision: revision,
            tasks: [
                TaskCard(
                    id: "board-foundation",
                    title: "Board foundation",
                    state: .active,
                    attentionKind: .none,
                    updatedAt: now,
                    shortSummary: "Building display, touch, and network foundations"
                ),
                TaskCard(
                    id: "mac-service",
                    title: "Mac service",
                    state: .active,
                    attentionKind: .none,
                    updatedAt: now.addingTimeInterval(-4),
                    shortSummary: "Serving a sanitized task snapshot"
                ),
                TaskCard(
                    id: "codex-decisions",
                    title: "Codex decisions",
                    state: .waiting,
                    attentionKind: .approval,
                    updatedAt: now.addingTimeInterval(-12),
                    shortSummary: "Review stays on Mac — fixed continue only"
                ),
            ]
        )
    }
}

public enum TaskSanitizer {
    public static func sanitize(_ task: TaskCard) -> TaskCard {
        let title = BoardDisplayText.sanitized(task.title, maximum: 80)
        let summary = BoardDisplayText.sanitized(task.shortSummary, maximum: 180)
        return TaskCard(
            id: clipped(task.id, maximum: 80),
            title: title.isEmpty ? "Codex task" : title,
            state: task.state,
            attentionKind: task.attentionKind,
            updatedAt: task.updatedAt,
            shortSummary: summary.isEmpty ? "No board-safe summary" : summary
        )
    }

    private static func clipped(_ value: String, maximum: Int) -> String {
        String(value.replacingOccurrences(of: "\n", with: " ").prefix(maximum))
    }
}
