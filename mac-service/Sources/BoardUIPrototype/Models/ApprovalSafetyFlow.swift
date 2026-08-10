public enum ApprovalSafetyStage: String, Sendable {
    case awaitingHold
    case holding
    case awaitingConfirmation
    case confirmationRecorded
    case expired
}

public enum ApprovalSafetyEvent: Sendable {
    case tap
    case holdStarted
    case holdCancelled
    case holdCompleted
    case confirm
    case expire
}

public enum ApprovalSafetyOutcome: Equatable, Sendable {
    case noAction
    /// A local fixture result only. No transport or Codex action is implied.
    case localConfirmationRecorded(requestID: String)
}

/// A transport-independent proof of the approval interaction contract.
///
/// One tap can never approve. A completed hold only reveals the second,
/// explicit confirmation step. The same request can be recorded once and
/// expiry makes every subsequent event inert. This type intentionally has no
/// networking dependency.
public struct ApprovalSafetyFlow: Sendable {
    public let requestID: String
    public private(set) var stage: ApprovalSafetyStage = .awaitingHold

    public init(requestID: String) {
        self.requestID = requestID
    }

    @discardableResult
    public mutating func apply(_ event: ApprovalSafetyEvent) -> ApprovalSafetyOutcome {
        switch (stage, event) {
        case (.awaitingHold, .holdStarted):
            stage = .holding
        case (.holding, .holdCompleted):
            stage = .awaitingConfirmation
        case (.holding, .holdCancelled), (.awaitingConfirmation, .holdCancelled):
            stage = .awaitingHold
        case (.awaitingConfirmation, .confirm):
            stage = .confirmationRecorded
            return .localConfirmationRecorded(requestID: requestID)
        case (.awaitingHold, .expire), (.holding, .expire), (.awaitingConfirmation, .expire):
            stage = .expired
        default:
            break
        }
        return .noAction
    }
}
