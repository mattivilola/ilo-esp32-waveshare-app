@testable import BoardHostCore
import BoardProtocol
import Foundation
import Testing

@Test func codexThreadDecodingIgnoresPrivateFieldsAndMapsDesktopHistoryHonestly() throws {
    let data = Data(#"""
    {
      "id": "019test",
      "name": "Set up ESP32 Mac controller",
      "preview": "full user prompt must not be forwarded",
      "cwd": "/private/project/path",
      "updatedAt": 1786338000,
      "status": {"type": "notLoaded"}
    }
    """#.utf8)
    let thread = try JSONDecoder().decode(CodexThreadRecord.self, from: data)
    let task = CodexHistoryMapper.task(from: thread)
    #expect(task.title == "Set up ESP32 Mac controller")
    #expect(task.state == .idle)
    #expect(task.attentionKind == .none)
    #expect(task.shortSummary == "Recent history · live Desktop status unavailable")
    #expect(!task.shortSummary.contains("prompt"))
    #expect(!task.shortSummary.contains("/private"))
}

@Test func codexActiveFlagsMapToNarrowAttentionKinds() {
    let approval = CodexThreadRecord(
        id: "approval",
        name: "Plan review",
        updatedAt: 1,
        status: CodexThreadStatus(type: "active", activeFlags: ["waitingOnApproval"])
    )
    let question = CodexThreadRecord(
        id: "question",
        name: "Clarification",
        updatedAt: 2,
        status: CodexThreadStatus(type: "active", activeFlags: ["waitingOnUserInput"])
    )
    #expect(CodexHistoryMapper.task(from: approval).attentionKind == .approval)
    #expect(CodexHistoryMapper.task(from: question).attentionKind == .question)
}

@Test func packagedAppCodexResolverSupportsExplicitPath() {
    let resolved = CodexExecutableResolver.resolve(environment: ["ILO_BOARD_CODEX_PATH": "/bin/sh"])
    #expect(resolved?.path == "/bin/sh")
}

@Test func codexContinuePolicyAllowsOnlyIdleOrUnloadedTasks() {
    for status in ["idle", "notLoaded"] {
        let thread = CodexThreadRecord(
            id: status,
            name: status,
            updatedAt: 1,
            status: CodexThreadStatus(type: status, activeFlags: nil)
        )
        #expect(CodexContinuationPolicy.allows(thread))
    }
    for status in ["active", "systemError", "completed", "unknown"] {
        let thread = CodexThreadRecord(
            id: status,
            name: status,
            updatedAt: 1,
            status: CodexThreadStatus(type: status, activeFlags: nil)
        )
        #expect(!CodexContinuationPolicy.allows(thread))
    }
}

@Test func codexContinuePolicyRequiresReplaySafeRequestIDs() {
    #expect(CodexContinuationPolicy.validRequestID("board-A12-9"))
    #expect(!CodexContinuationPolicy.validRequestID(""))
    #expect(!CodexContinuationPolicy.validRequestID("contains spaces"))
    #expect(!CodexContinuationPolicy.validRequestID(String(repeating: "a", count: 65)))
}

@Test func fixedCodexContinueIsOffByDefaultAndRevocable() throws {
    let suite = "CodexContinueFeatureControllerTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let controller = CodexContinueFeatureController(defaults: defaults)
    #expect(!controller.isEnabled)
    controller.setEnabled(true)
    #expect(controller.isEnabled)
    controller.setEnabled(false)
    #expect(!controller.isEnabled)
}
