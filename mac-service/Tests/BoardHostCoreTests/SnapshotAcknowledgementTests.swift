@testable import BoardHostCore
import BoardProtocol
import Testing

@Test func snapshotAcknowledgementRequiresASentIncreasingRevision() {
    var tracker = SnapshotAcknowledgementTracker()
    tracker.sent(revision: 3)

    let future = tracker.accept(SnapshotAcknowledgement(revision: 4))
    let applied = tracker.accept(SnapshotAcknowledgement(revision: 2))
    let replay = tracker.accept(SnapshotAcknowledgement(revision: 2))
    let latest = tracker.accept(SnapshotAcknowledgement(revision: 3))

    #expect(!future)
    #expect(applied)
    #expect(!replay)
    #expect(latest)
}
