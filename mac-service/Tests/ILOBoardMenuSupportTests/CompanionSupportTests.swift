import Foundation
import Testing
@testable import ILOBoardMenuSupport

@Test func connectionHistoryIsNewestFirstAndBounded() {
    var history = ConnectionHistoryLog(capacity: 2)
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    history.record(.serviceStarting, at: start)
    history.record(.waitingForBoard, at: start.addingTimeInterval(10))
    history.record(.boardConnected, at: start.addingTimeInterval(20))

    #expect(history.entries.map(\.kind) == [.boardConnected, .waitingForBoard])
}

@Test func connectionHistorySuppressesImmediateDuplicateNoise() {
    var history = ConnectionHistoryLog()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    history.record(.waitingForBoard, at: start)
    history.record(.waitingForBoard, at: start.addingTimeInterval(1))

    #expect(history.entries.count == 1)
}

@Test func connectionHistoryRoundTripsWithoutPrivateContext() throws {
    var history = ConnectionHistoryLog()
    history.record(.boardConnected, at: Date(timeIntervalSince1970: 1_700_000_000))

    let restored = ConnectionHistoryLog.decode(try history.encoded())

    #expect(restored.entries == history.entries)
}

@Test func diagnosticsContainOnlyBoundedOperationalState() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let snapshot = DiagnosticSnapshot(
        generatedAt: date,
        appVersion: "1.2.3 (45)",
        macOSVersion: "Version 15.0",
        serviceState: "Ready",
        launchAtLoginState: .enabled,
        lastSync: date,
        activity: [ConnectionHistoryEntry(kind: .boardConnected, date: date)]
    )

    let text = DiagnosticSummary.render(snapshot)

    #expect(text.contains("App version: 1.2.3 (45)"))
    #expect(text.contains("Board connected"))
    #expect(text.contains("Launch at login: On"))
    #expect(text.contains("identifiers, network addresses, ports, file paths"))
}

@MainActor
@Test func launchAtLoginChangesOnlyAfterExplicitAction() {
    let service = TestLaunchAtLoginService()
    let controller = LaunchAtLoginController(service: service)

    #expect(controller.state == .disabled)
    #expect(service.registerCount == 0)

    controller.enable()

    #expect(controller.state == .enabled)
    #expect(service.registerCount == 1)
}

@MainActor
@Test func launchAtLoginNeverExportsRegistrationErrors() {
    let service = TestLaunchAtLoginService()
    service.registerError = TestError.registrationFailed
    let controller = LaunchAtLoginController(service: service)

    controller.enable()

    #expect(controller.state == .disabled)
    #expect(controller.notice == "Couldn’t enable launch at login. Install the signed app in Applications and try again.")
    #expect(controller.notice?.contains("private failure context") == false)
}

private enum TestError: Error {
    case registrationFailed
}

@MainActor
private final class TestLaunchAtLoginService: LaunchAtLoginServicing {
    var state: LaunchAtLoginState = .disabled
    var registerCount = 0
    var registerError: Error?

    func register() throws {
        registerCount += 1
        if let registerError {
            throw registerError
        }
        state = .enabled
    }

    func unregister() throws {
        state = .disabled
    }

    func openSystemSettings() {}
}
