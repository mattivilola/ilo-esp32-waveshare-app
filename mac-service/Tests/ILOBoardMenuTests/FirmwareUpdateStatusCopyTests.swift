import Foundation
import Testing

@testable import ILOBoardMenu

@MainActor
@Test func disabledFirmwareUpdateCopyDoesNotImplyUSBIsDisconnected() {
    let status = HostStatusStore.firmwareUpdatePresentation(for: .disabled)

    #expect(status.title == "OTA firmware not installed")
    #expect(status.detail.contains("USB and Wi-Fi can be connected normally"))
    #expect(!status.title.localizedCaseInsensitiveContains("bridge"))
}
