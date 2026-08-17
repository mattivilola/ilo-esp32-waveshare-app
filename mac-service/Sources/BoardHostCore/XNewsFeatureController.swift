import Foundation

public struct XNewsFeatureStatus: Equatable, Sendable {
    public let cadence: XNewsRefreshCadence
    public let apiKeyConfigured: Bool
    public let lastAttemptAt: Date?
    public let lastCostInUSDTicks: Int64?

    public init(
        cadence: XNewsRefreshCadence,
        apiKeyConfigured: Bool,
        lastAttemptAt: Date? = nil,
        lastCostInUSDTicks: Int64? = nil
    ) {
        self.cadence = cadence
        self.apiKeyConfigured = apiKeyConfigured
        self.lastAttemptAt = lastAttemptAt
        self.lastCostInUSDTicks = lastCostInUSDTicks
    }

    public var isConfigured: Bool {
        cadence != .off
    }

    public var isEnabled: Bool {
        isConfigured && apiKeyConfigured
    }
}

public struct XNewsFeatureController: Sendable {
    private let settingsStore: XNewsRefreshSettingsStore
    private let apiKeyStore: XAIAPIKeyStore
    private let availabilityOverride: Bool?

    public init(
        settingsStore: XNewsRefreshSettingsStore = XNewsRefreshSettingsStore(),
        apiKeyStore: XAIAPIKeyStore = XAIAPIKeyStore()
    ) {
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        availabilityOverride = nil
    }

    public init(settingsStore: XNewsRefreshSettingsStore, apiKeyConfigured: Bool) {
        self.settingsStore = settingsStore
        apiKeyStore = XAIAPIKeyStore()
        availabilityOverride = apiKeyConfigured
    }

    public func status() -> XNewsFeatureStatus {
        let settings = settingsStore.load()
        return XNewsFeatureStatus(
            cadence: settings.consentVersion == XNewsRefreshSettings.currentConsentVersion
                ? settings.cadence
                : .off,
            apiKeyConfigured: availabilityOverride ?? apiKeyStore.isConfigured,
            lastAttemptAt: settings.lastAttemptAt,
            lastCostInUSDTicks: settings.lastCostInUSDTicks
        )
    }

    public func enable(
        cadence: XNewsRefreshCadence,
        explicitlyAllowsPaidAPI: Bool
    ) throws {
        guard cadence != .off else {
            try disable()
            return
        }
        guard explicitlyAllowsPaidAPI else { throw GrokXNewsError.explicitConsentRequired }
        guard status().apiKeyConfigured else { throw XAIResponsesError.missingAPIKey }
        let previous = settingsStore.load()
        try settingsStore.save(XNewsRefreshSettings(
            cadence: cadence,
            consentVersion: XNewsRefreshSettings.currentConsentVersion,
            lastAttemptAt: previous.lastAttemptAt,
            lastCostInUSDTicks: previous.lastCostInUSDTicks
        ))
    }

    public func disable() throws {
        let previous = settingsStore.load()
        try settingsStore.save(XNewsRefreshSettings(
            cadence: .off,
            consentVersion: XNewsRefreshSettings.currentConsentVersion,
            lastAttemptAt: previous.lastAttemptAt,
            lastCostInUSDTicks: previous.lastCostInUSDTicks
        ))
    }
}
