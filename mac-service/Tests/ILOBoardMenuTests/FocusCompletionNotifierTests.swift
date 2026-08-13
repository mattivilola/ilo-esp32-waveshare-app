@testable import ILOBoardMenu
import Foundation
import Testing

@Test func focusCompletionReceiptDeduplicatesRetriedBoardEvents() {
    let suite = "FocusCompletionNotifierTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(FocusCompletionReceipt.shouldNotify(eventID: "focus-1770000000", defaults: defaults))
    #expect(!FocusCompletionReceipt.shouldNotify(eventID: "focus-1770000000", defaults: defaults))
    #expect(FocusCompletionReceipt.shouldNotify(eventID: "focus-1770000060", defaults: defaults))
}
