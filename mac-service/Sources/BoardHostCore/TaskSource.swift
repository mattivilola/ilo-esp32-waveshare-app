import BoardProtocol
import Foundation

public protocol TaskSource: Sendable {
    func snapshot(revision: UInt64) async throws -> DashboardSnapshot
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
                    shortSummary: "Review on Mac — remote actions are disabled"
                ),
            ]
        )
    }
}

public enum TaskSanitizer {
    public static func sanitize(_ task: TaskCard) -> TaskCard {
        TaskCard(
            id: clipped(task.id, maximum: 80),
            title: clipped(task.title, maximum: 80),
            state: task.state,
            attentionKind: task.attentionKind,
            updatedAt: task.updatedAt,
            shortSummary: clipped(task.shortSummary, maximum: 180)
        )
    }

    private static func clipped(_ value: String, maximum: Int) -> String {
        String(value.replacingOccurrences(of: "\n", with: " ").prefix(maximum))
    }
}

