import Foundation

public final class CodexContinueFeatureController: @unchecked Sendable {
    private let defaults: UserDefaults
    // This consent intentionally does not inherit the earlier Continue-only opt-in.
    private static let enabledKey = "ilo-board.codex-fixed-actions.v2"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
    }
}
