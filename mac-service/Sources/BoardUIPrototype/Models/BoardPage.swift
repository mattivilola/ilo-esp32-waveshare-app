import Foundation

public enum BoardPage: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case codex
    case weather
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .codex: "Codex"
        case .weather: "Weather"
        case .settings: "Settings"
        }
    }

    var eyebrow: String {
        switch self {
        case .dashboard: "ILO / WORK PULSE"
        case .codex: "ILO / CODEX"
        case .weather: "ILO / WEATHER"
        case .settings: "ILO / SETTINGS"
        }
    }
}
