import SwiftUI

/// Hardware-independent states used to review the fixed 1024 x 600 layout.
///
/// These scenarios are deliberately separate from live transport models. They
/// provide deterministic visual fixtures and never imply that hardware behavior
/// has been verified.
public enum BoardPreviewScenario: String, CaseIterable, Identifiable, Sendable {
    case offline
    case loading
    case stale
    case error
    case longText = "long-text"
    case privacy
    case sleep
    case reconnect
    case screensaver
    case approvalRequest = "approval-request"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .offline: "Mac offline"
        case .loading: "Codex loading"
        case .stale: "Weather stale"
        case .error: "Weather error"
        case .longText: "Long task text"
        case .privacy: "Privacy enabled"
        case .sleep: "Display asleep"
        case .reconnect: "Mac reconnecting"
        case .screensaver: "Pulse screensaver"
        case .approvalRequest: "Approval request safety"
        }
    }

    public var page: BoardPage {
        switch self {
        case .offline, .privacy, .reconnect, .sleep, .screensaver: .dashboard
        case .loading, .longText, .approvalRequest: .codex
        case .stale, .error: .weather
        }
    }

    var connectionLabel: String {
        switch self {
        case .offline: "MAC OFFLINE"
        case .reconnect: "RECONNECTING"
        case .sleep: "DISPLAY ASLEEP"
        case .approvalRequest: "FIXTURE · NO ACTION"
        default: "MAC ONLINE"
        }
    }

    var connectionColor: Color {
        switch self {
        case .offline, .error: BoardPalette.amber
        case .reconnect, .loading: BoardPalette.cyan
        case .approvalRequest: BoardPalette.amber
        default: BoardPalette.signal
        }
    }
}
