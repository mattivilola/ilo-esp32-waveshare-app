import BoardHostCore
import BoardProtocol
import Foundation
import Testing

@Test func sanitizerBoundsAndFlattensBoardVisibleText() {
    let task = TaskCard(
        id: String(repeating: "i", count: 120),
        title: "Line one\nLine two",
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

@Test func mockSourceExposesReadOnlyCapability() async throws {
    let snapshot = try await MockTaskSource().snapshot(revision: 7)
    #expect(snapshot.revision == 7)
    #expect(snapshot.capabilities == ["tasks.read", "macPower.read"])
    #expect(snapshot.tasks.contains { $0.attentionKind == .approval })
}
