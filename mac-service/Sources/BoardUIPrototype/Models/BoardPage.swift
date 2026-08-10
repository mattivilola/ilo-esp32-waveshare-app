import Foundation

public enum BoardPage: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case codex
    case xNews = "x-news"
    case weather
    case settings

    public var id: String { rawValue }

    public static func visiblePages(xNewsEnabled: Bool) -> [BoardPage] {
        xNewsEnabled ? allCases : allCases.filter { $0 != .xNews }
    }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .codex: "Codex"
        case .xNews: "X News"
        case .weather: "Weather"
        case .settings: "Settings"
        }
    }

    var eyebrow: String {
        switch self {
        case .dashboard: "ILO / WORK PULSE"
        case .codex: "ILO / CODEX"
        case .xNews: "ILO / X NEWS"
        case .weather: "ILO / WEATHER"
        case .settings: "ILO / SETTINGS"
        }
    }
}
