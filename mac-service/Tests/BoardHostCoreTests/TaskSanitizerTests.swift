import BoardHostCore
import BoardProtocol
import Foundation
import Testing

@Test func sanitizerBoundsAndFlattensBoardVisibleText() {
    let task = TaskCard(
        id: String(repeating: "i", count: 120),
        title: "Line one\nLine two 🤖",
        state: .active,
        attentionKind: .none,
        updatedAt: Date(timeIntervalSince1970: 0),
        shortSummary: String(repeating: "s", count: 240)
    )
    let sanitized = TaskSanitizer.sanitize(task)
    #expect(sanitized.id.count == 80)
    #expect(sanitized.title == "Line one Line two")
    #expect(sanitized.shortSummary.count == 180)
}

@Test func sanitizerMapsUnsupportedCodexGlyphsToBoardSafeASCII() {
    let task = TaskCard(
        id: "glyphs",
        title: "Päätös: Codex’s plan — ready… 🚀",
        state: .waiting,
        attentionKind: .approval,
        updatedAt: Date(timeIntervalSince1970: 0),
        shortSummary: "Review • then confirm"
    )

    let sanitized = TaskSanitizer.sanitize(task)
    #expect(sanitized.title == "Paatos: Codex's plan - ready...")
    #expect(sanitized.shortSummary == "Review / then confirm")
    #expect(sanitized.title.unicodeScalars.allSatisfy { $0.isASCII })
    #expect(sanitized.shortSummary.unicodeScalars.allSatisfy { $0.isASCII })
}

@Test func mockSourceExposesReadOnlyCapability() async throws {
    let snapshot = try await MockTaskSource().snapshot(revision: 7)
    #expect(snapshot.revision == 7)
    #expect(snapshot.capabilities == ["tasks.read", "macPower.read", "hostTime.read"])
    #expect(snapshot.tasks.contains { $0.attentionKind == .approval })
}

@Test func taskSourcesRejectControlUnlessExplicitlyImplemented() async {
    let outcome = await MockTaskSource().continueTask(id: "codex-decisions", requestID: "fixture-1")
    guard case .unavailable = outcome else {
        Issue.record("Mock/read-only task sources must not claim a real Codex action")
        return
    }
}
