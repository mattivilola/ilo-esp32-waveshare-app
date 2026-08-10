import BoardUIPrototype
import Testing

@Test func boardPageOrderMatchesSwipeInformationArchitecture() {
    #expect(BoardPage.allCases == [.dashboard, .codex, .xNews, .weather, .settings])
    #expect(BoardPage.allCases.map(\.title) == ["Dashboard", "Codex", "X News", "Weather", "Settings"])
}

@Test func validationScenarioOrderAndTargetPagesStayStable() {
    #expect(BoardPreviewScenario.allCases.map(\.rawValue) == [
        "offline", "loading", "stale", "error", "long-text", "privacy", "sleep", "reconnect",
        "screensaver", "approval-request"
    ])
    #expect(BoardPreviewScenario.allCases.map(\.page) == [
        .dashboard, .codex, .weather, .weather, .codex, .dashboard, .dashboard, .dashboard,
        .dashboard, .codex
    ])
}

@Test func approvalRequiresHoldThenSeparateConfirmation() {
    var flow = ApprovalSafetyFlow(requestID: "fixture-7A2F")

    #expect(flow.apply(.tap) == .noAction)
    #expect(flow.apply(.confirm) == .noAction)
    #expect(flow.apply(.holdCompleted) == .noAction)
    #expect(flow.stage == .awaitingHold)
    #expect(flow.apply(.holdStarted) == .noAction)
    #expect(flow.stage == .holding)
    #expect(flow.apply(.holdCompleted) == .noAction)
    #expect(flow.stage == .awaitingConfirmation)
    #expect(flow.apply(.confirm) == .localConfirmationRecorded(requestID: "fixture-7A2F"))
    #expect(flow.stage == .confirmationRecorded)
    #expect(flow.apply(.confirm) == .noAction)
}

@Test func approvalCancellationAndExpiryAreInert() {
    var cancelled = ApprovalSafetyFlow(requestID: "cancelled")
    #expect(cancelled.apply(.holdStarted) == .noAction)
    #expect(cancelled.apply(.holdCancelled) == .noAction)
    #expect(cancelled.stage == .awaitingHold)
    #expect(cancelled.apply(.confirm) == .noAction)

    var expired = ApprovalSafetyFlow(requestID: "expired")
    #expect(expired.apply(.expire) == .noAction)
    #expect(expired.stage == .expired)
    #expect(expired.apply(.holdCompleted) == .noAction)
    #expect(expired.apply(.confirm) == .noAction)
}
