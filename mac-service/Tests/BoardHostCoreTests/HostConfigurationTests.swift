@testable import BoardHostCore
import Foundation
import Testing

@Test func hostConfigurationLoadsProvisionedNonsecretMetadata() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-host-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("board.json")
    try Data(#"{"boardID":"ilo-test_board.1","port":47472,"protocolVersion":1,"usbSerialNumber":"94:a9:90:ca:5b:7c"}"#.utf8).write(to: url)

    let configuration = try HostConfiguration.load(from: url)
    #expect(configuration.boardID == "ilo-test_board.1")
    #expect(configuration.port == 47_472)
    #expect(configuration.protocolVersion == 1)
    #expect(configuration.usbSerialNumber == "94:a9:90:ca:5b:7c")
}

@Test func legacyHostConfigurationWithoutUSBIdentityRemainsCompatible() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-host-legacy-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"boardID":"ilo-test","port":47472,"protocolVersion":1}"#.utf8).write(to: url)

    let configuration = try HostConfiguration.load(from: url)
    #expect(configuration.usbSerialNumber == nil)
}

@Test func usbPresenceRequiresTheProvisionedHardwareSerialForAPairedMatch() {
    let paired = USBBoardDevice(
        path: "/dev/cu.usbmodem1101",
        serialNumber: "94:A9:90:CA:5B:7C",
        vendorID: 0x303A,
        productID: 0x1001
    )
    let other = USBBoardDevice(
        path: "/dev/cu.usbmodem2101",
        serialNumber: "AA:BB:CC:DD:EE:FF",
        vendorID: 0x303A,
        productID: 0x1001
    )

    #expect(USBBoardMatcher.presence(
        devices: [other, paired],
        configuredSerialNumber: "94a990ca5b7c"
    ) == .paired(path: paired.path))
    #expect(USBBoardMatcher.presence(
        devices: [other],
        configuredSerialNumber: "94a990ca5b7c"
    ) == .compatible(path: other.path))
    #expect(USBBoardMatcher.presence(
        devices: [],
        configuredSerialNumber: "94a990ca5b7c"
    ) == .disconnected)
}

@Test func hostConfigurationRejectsUnsupportedProtocol() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-host-invalid-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"boardID":"ilo-test","port":47472,"protocolVersion":99}"#.utf8).write(to: url)

    #expect(throws: HostConfigurationError.self) {
        try HostConfiguration.load(from: url)
    }
}

@Test func companionUsesAnAppOwnedKeychainServiceDistinctFromTheCLI() {
    #expect(KeychainPSKStore.legacyService == "com.iloapps.iloboard.host.psk")
    #expect(KeychainPSKStore.companionService == "com.iloapps.iloboard.menu.psk.v1")
    #expect(KeychainPSKStore.companionService != KeychainPSKStore.legacyService)
}

@Test func onlyTheStableSignedCompanionUsesItsAppOwnedCredential() {
    #expect(KeychainPSKStore.shouldUseCompanionCredential(
        bundleIdentifier: "com.iloapps.iloboard.menu",
        teamIdentifier: "MM233FKU38"
    ))
    #expect(!KeychainPSKStore.shouldUseCompanionCredential(
        bundleIdentifier: "com.iloapps.iloboard.menu",
        teamIdentifier: nil
    ))
    #expect(!KeychainPSKStore.shouldUseCompanionCredential(
        bundleIdentifier: nil,
        teamIdentifier: "MM233FKU38"
    ))
    #expect(!KeychainPSKStore.shouldUseCompanionCredential(
        bundleIdentifier: "com.example.copy",
        teamIdentifier: "MM233FKU38"
    ))
}
