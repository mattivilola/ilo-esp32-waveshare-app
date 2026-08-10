import BoardUIPrototype
import Testing

@Test func boardPageOrderMatchesSwipeInformationArchitecture() {
    #expect(BoardPage.allCases == [.dashboard, .codex, .weather, .settings])
    #expect(BoardPage.allCases.map(\.title) == ["Dashboard", "Codex", "Weather", "Settings"])
}
