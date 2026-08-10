import BoardProtocol
import Foundation
import IOKit.ps

public protocol MacPowerStatusProviding: Sendable {
    func currentStatus() async -> MacPowerStatus?
}

public struct RawMacPowerSource: Equatable, Sendable {
    public let type: String
    public let currentCapacity: Int
    public let maximumCapacity: Int
    public let isCharging: Bool
    public let powerSourceState: String

    public init(
        type: String,
        currentCapacity: Int,
        maximumCapacity: Int,
        isCharging: Bool,
        powerSourceState: String
    ) {
        self.type = type
        self.currentCapacity = currentCapacity
        self.maximumCapacity = maximumCapacity
        self.isCharging = isCharging
        self.powerSourceState = powerSourceState
    }
}

public enum MacPowerStatusMapper {
    public static func map(_ source: RawMacPowerSource) -> MacPowerStatus? {
        guard source.type == kIOPSInternalBatteryType,
              source.currentCapacity >= 0,
              source.maximumCapacity > 0 else {
            return nil
        }

        let ratio = Double(source.currentCapacity) / Double(source.maximumCapacity)
        guard ratio.isFinite else { return nil }
        let percent = min(max(Int((ratio * 100).rounded()), 0), 100)
        let state: MacPowerState
        if source.isCharging {
            state = .charging
        } else if source.powerSourceState == kIOPSACPowerValue {
            state = percent == 100 ? .full : .powerAdapter
        } else if source.powerSourceState == kIOPSBatteryPowerValue {
            state = .battery
        } else {
            return nil
        }
        return MacPowerStatus(levelPercent: percent, state: state)
    }
}

public struct SystemMacPowerStatusSource: MacPowerStatusProviding {
    public init() {}

    public func currentStatus() async -> MacPowerStatus? {
        let information = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(information).takeRetainedValue() as NSArray
        for item in sources {
            guard let unmanagedDescription = IOPSGetPowerSourceDescription(information, item as CFTypeRef) else {
                continue
            }
            let description = unmanagedDescription.takeUnretainedValue() as NSDictionary
            guard let raw = rawSource(from: description),
                  let status = MacPowerStatusMapper.map(raw) else {
                continue
            }
            return status
        }
        return nil
    }

    private func rawSource(from description: NSDictionary) -> RawMacPowerSource? {
        guard let type = description[kIOPSTypeKey] as? String,
              let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
              let maximum = description[kIOPSMaxCapacityKey] as? NSNumber,
              let charging = description[kIOPSIsChargingKey] as? NSNumber,
              let sourceState = description[kIOPSPowerSourceStateKey] as? String else {
            return nil
        }
        return RawMacPowerSource(
            type: type,
            currentCapacity: current.intValue,
            maximumCapacity: maximum.intValue,
            isCharging: charging.boolValue,
            powerSourceState: sourceState
        )
    }
}

public struct MockMacPowerStatusSource: MacPowerStatusProviding {
    public init() {}

    public func currentStatus() async -> MacPowerStatus? {
        MacPowerStatus(levelPercent: 82, state: .charging)
    }
}

public actor CachedMacPowerStatusSource: MacPowerStatusProviding {
    private let source: any MacPowerStatusProviding
    private let refreshInterval: TimeInterval
    private var cachedAt = Date.distantPast
    private var cachedStatus: MacPowerStatus?
    private var hasCachedValue = false

    public init(
        source: any MacPowerStatusProviding = SystemMacPowerStatusSource(),
        refreshInterval: TimeInterval = 30
    ) {
        self.source = source
        self.refreshInterval = max(1, refreshInterval)
    }

    public func currentStatus() async -> MacPowerStatus? {
        let now = Date()
        if hasCachedValue, now.timeIntervalSince(cachedAt) < refreshInterval {
            return cachedStatus
        }
        let status = await source.currentStatus()
        cachedStatus = status
        cachedAt = now
        hasCachedValue = true
        return status
    }
}
