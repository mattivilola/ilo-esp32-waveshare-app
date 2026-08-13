@testable import BoardUIPrototype
import Testing

@Test func focusPreviewMathUsesStableCountdownAndProgress() {
    #expect(FocusPreviewMath.countdown(1_499) == "24:59")
    #expect(FocusPreviewMath.countdown(-1) == "00:00")
    #expect(FocusPreviewMath.progress(remainingSeconds: 750, totalSeconds: 1_500) == 0.5)
    #expect(FocusPreviewMath.progress(remainingSeconds: 0, totalSeconds: 1_500) == 1)
}

@Test func boardPageOrderMatchesSwipeInformationArchitecture() {
    #expect(BoardPage.allCases == [.dashboard, .codex, .xNews, .weather, .settings])
    #expect(BoardPage.allCases.map(\.title) == ["Dashboard", "Codex", "X News", "Weather", "Settings"])
    #expect(BoardPage.visiblePages(codexEnabled: true, xNewsEnabled: true) == BoardPage.allCases)
    #expect(BoardPage.visiblePages(codexEnabled: true, xNewsEnabled: false) == [
        .dashboard, .codex, .weather, .settings,
    ])
    #expect(BoardPage.visiblePages(codexEnabled: false, xNewsEnabled: true) == [
        .dashboard, .xNews, .weather, .settings,
    ])
    #expect(BoardPage.visiblePages(codexEnabled: false, xNewsEnabled: false) == [
        .dashboard, .weather, .settings,
    ])
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

@Test func pointerDragScrollLocksToDirectionAndClampsToFeedBounds() {
    #expect(PointerDragScrollMath.axis(translationX: 2, translationY: -3) == .pending)
    #expect(PointerDragScrollMath.axis(translationX: 8, translationY: -40) == .vertical)
    #expect(PointerDragScrollMath.axis(translationX: 40, translationY: -8) == .horizontal)

    #expect(PointerDragScrollMath.originY(
        startOriginY: 0,
        translationY: 80,
        minimumY: 0,
        maximumY: 120
    ) == 80)
    #expect(PointerDragScrollMath.originY(
        startOriginY: 80,
        translationY: 80,
        minimumY: 0,
        maximumY: 120
    ) == 120)
    #expect(PointerDragScrollMath.originY(
        startOriginY: 40,
        translationY: -80,
        minimumY: 0,
        maximumY: 120
    ) == 0)
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
