import BoardUIPrototype
import Testing

@Test func boardPageOrderMatchesSwipeInformationArchitecture() {
    #expect(BoardPage.allCases == [.dashboard, .codex, .weather, .settings])
    #expect(BoardPage.allCases.map(\.title) == ["Dashboard", "Codex", "Weather", "Settings"])
}

@Test func validationScenarioOrderAndTargetPagesStayStable() {
    #expect(BoardPreviewScenario.allCases.map(\.rawValue) == [
        "offline", "loading", "stale", "error", "long-text", "privacy", "sleep", "reconnect"
    ])
    #expect(BoardPreviewScenario.allCases.map(\.page) == [
        .dashboard, .codex, .weather, .weather, .codex, .dashboard, .dashboard, .dashboard
    ])
}
