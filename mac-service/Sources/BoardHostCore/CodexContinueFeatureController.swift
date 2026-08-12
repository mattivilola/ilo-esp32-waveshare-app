import Foundation

public final class CodexContinueFeatureController: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let enabledKey = "ilo-board.codex-fixed-continue.v1"

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
