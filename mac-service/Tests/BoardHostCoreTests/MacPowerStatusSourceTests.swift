import BoardHostCore
import BoardProtocol
import Testing

@Test func macPowerMapperProducesOnlyBoundedCoarseState() {
    let charging = MacPowerStatusMapper.map(
        RawMacPowerSource(
            type: "InternalBattery",
            currentCapacity: 164,
            maximumCapacity: 200,
            isCharging: true,
            powerSourceState: "AC Power"
        )
    )
    let heldByAdapter = MacPowerStatusMapper.map(
        RawMacPowerSource(
            type: "InternalBattery",
            currentCapacity: 80,
            maximumCapacity: 100,
            isCharging: false,
            powerSourceState: "AC Power"
        )
    )
    let battery = MacPowerStatusMapper.map(
        RawMacPowerSource(
            type: "InternalBattery",
            currentCapacity: 45,
            maximumCapacity: 100,
            isCharging: false,
            powerSourceState: "Battery Power"
        )
    )

    #expect(charging == MacPowerStatus(levelPercent: 82, state: .charging))
    #expect(heldByAdapter == MacPowerStatus(levelPercent: 80, state: .powerAdapter))
    #expect(battery == MacPowerStatus(levelPercent: 45, state: .battery))
}

@Test func macPowerMapperTreatsUnsupportedOrInvalidSourcesAsUnavailable() {
    #expect(MacPowerStatusMapper.map(
        RawMacPowerSource(
            type: "UPS",
            currentCapacity: 50,
            maximumCapacity: 100,
            isCharging: false,
            powerSourceState: "Battery Power"
        )
    ) == nil)
    #expect(MacPowerStatusMapper.map(
        RawMacPowerSource(
            type: "InternalBattery",
            currentCapacity: 50,
            maximumCapacity: 0,
            isCharging: false,
            powerSourceState: "Battery Power"
        )
    ) == nil)
}

@Test func macPowerCacheBoundsSystemPolling() async {
    let source = CountingPowerSource()
    let cache = CachedMacPowerStatusSource(source: source, refreshInterval: 60)

    let first = await cache.currentStatus()
    let second = await cache.currentStatus()

    #expect(first == MacPowerStatus(levelPercent: 73, state: .battery))
    #expect(second == first)
    #expect(await source.readCount() == 1)
}

@Test func mockMacPowerMatchesTheDashboardPreview() async {
    let status = await MockMacPowerStatusSource().currentStatus()
    #expect(status == MacPowerStatus(levelPercent: 82, state: .charging))
}

private actor CountingPowerSource: MacPowerStatusProviding {
    private var count = 0

    func currentStatus() async -> MacPowerStatus? {
        count += 1
        return MacPowerStatus(levelPercent: 73, state: .battery)
    }

    func readCount() -> Int { count }
}
