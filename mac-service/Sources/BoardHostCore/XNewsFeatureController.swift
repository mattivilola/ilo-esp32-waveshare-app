import Foundation

public struct XNewsFeatureStatus: Equatable, Sendable {
    public let cadence: XNewsRefreshCadence
    public let grokAvailable: Bool
    public let lastAttemptAt: Date?

    public init(cadence: XNewsRefreshCadence, grokAvailable: Bool, lastAttemptAt: Date? = nil) {
        self.cadence = cadence
        self.grokAvailable = grokAvailable
        self.lastAttemptAt = lastAttemptAt
    }

    public var isConfigured: Bool {
        cadence != .off
    }

    public var isEnabled: Bool {
        isConfigured && grokAvailable
    }
}

public struct XNewsFeatureController: Sendable {
    private let settingsStore: XNewsRefreshSettingsStore
    private let environment: [String: String]
    private let availabilityOverride: Bool?

    public init(
        settingsStore: XNewsRefreshSettingsStore = XNewsRefreshSettingsStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.settingsStore = settingsStore
        self.environment = environment
        availabilityOverride = nil
    }

    public init(settingsStore: XNewsRefreshSettingsStore, grokAvailable: Bool) {
        self.settingsStore = settingsStore
        environment = [:]
        availabilityOverride = grokAvailable
    }

    public func status() -> XNewsFeatureStatus {
        let settings = settingsStore.load()
        return XNewsFeatureStatus(
            cadence: settings.cadence,
            grokAvailable: availabilityOverride ?? (GrokExecutableResolver.resolve(environment: environment) != nil),
            lastAttemptAt: settings.lastAttemptAt
        )
    }

    public func enable(
        cadence: XNewsRefreshCadence,
        explicitlyAllowsGrokTools: Bool
    ) throws {
        guard cadence != .off else {
            try disable()
            return
        }
        guard explicitlyAllowsGrokTools else { throw GrokXNewsError.explicitConsentRequired }
        guard status().grokAvailable else { throw GrokXNewsError.executableNotFound }
        let previous = settingsStore.load()
        try settingsStore.save(XNewsRefreshSettings(
            cadence: cadence,
            consentVersion: previous.consentVersion,
            lastAttemptAt: previous.lastAttemptAt
        ))
    }

    public func disable() throws {
        let previous = settingsStore.load()
        try settingsStore.save(XNewsRefreshSettings(
            cadence: .off,
            consentVersion: previous.consentVersion,
            lastAttemptAt: previous.lastAttemptAt
        ))
    }
}
