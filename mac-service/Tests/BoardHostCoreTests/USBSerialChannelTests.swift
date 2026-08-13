@testable import BoardHostCore
import CryptoKit
import Foundation
import Testing

@Test func usbFallbackAuthenticationAndEncryptionAreBoundToNoncesIdentityDirectionAndSequence() throws {
    let secret = Data((0..<32).map(UInt8.init))
    let clientNonce = Data((32..<64).map(UInt8.init))
    let boardNonce = Data((64..<96).map(UInt8.init))
    let boardID = "ilo-test-board"

    let challenge = USBSessionCryptography.authenticationCode(
        label: "challenge",
        secret: secret,
        clientNonce: clientNonce,
        boardNonce: boardNonce,
        boardID: boardID
    )
    let auth = USBSessionCryptography.authenticationCode(
        label: "auth",
        secret: secret,
        clientNonce: clientNonce,
        boardNonce: boardNonce,
        boardID: boardID
    )
    #expect(challenge.count == 32)
    #expect(challenge != auth)

    let key = USBSessionCryptography.sessionKey(
        secret: secret,
        clientNonce: clientNonce,
        boardNonce: boardNonce
    )
    let payload = Data("\0\0\0\u{11}{\"type\":\"helloAck\"}".utf8)
    let sealed = try USBSessionCryptography.seal(payload, key: key, direction: "M", sequence: 1)
    #expect(try USBSessionCryptography.open(sealed, key: key, direction: "M", sequence: 1) == payload)
    #expect(throws: (any Error).self) {
        try USBSessionCryptography.open(sealed, key: key, direction: "B", sequence: 1)
    }
    #expect(throws: (any Error).self) {
        try USBSessionCryptography.open(sealed, key: key, direction: "M", sequence: 2)
    }
}

@Test func usbFallbackHexCodecRejectsMalformedInput() {
    let bytes = Data([0x00, 0x7F, 0xA5, 0xFF])
    #expect(USBSessionCryptography.hex(bytes) == "007fa5ff")
    #expect(USBSessionCryptography.data(hex: "007fa5ff") == bytes)
    #expect(USBSessionCryptography.data(hex: "abc") == nil)
    #expect(USBSessionCryptography.data(hex: "zz") == nil)
}

@Test func usbFallbackRetriesOutsideInstalledFirmwareAuthenticationWindow() {
    #expect(USBSerialBoardConnectionChannel.challengeAttemptMilliseconds > 5_000)
    #expect(USBSerialBoardConnectionChannel.challengeAttemptCount >= 2)
}
