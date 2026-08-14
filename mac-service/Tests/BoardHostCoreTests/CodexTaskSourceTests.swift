@testable import BoardHostCore
import BoardProtocol
import Foundation
import Testing

private actor UnavailableCodexAppServer: CodexAppServerAccess {
    func listThreads(limit: Int) async throws -> [CodexThreadRecord] {
        throw CodexSourceError.requestTimedOut
    }

    func recentTurns(threadID: String, turnLimit: Int) async throws -> [CodexTurnRecord] {
        throw CodexSourceError.requestTimedOut
    }

    func continueThread(id threadID: String, requestID: String) async throws {
        throw CodexSourceError.requestTimedOut
    }

    func respondToPlan(
        id threadID: String,
        plan: String,
        model: String,
        action: CodexTaskAction,
        requestID: String
    ) async throws {
        throw CodexSourceError.requestTimedOut
    }
}

private actor RecordingCodexAppServer: CodexAppServerAccess {
    let threads: [CodexThreadRecord]
    let turns: [CodexTurnRecord]
    private(set) var requestedLimits = [Int]()
    private(set) var planActions = [CodexTaskAction]()

    init(threads: [CodexThreadRecord], turns: [CodexTurnRecord] = []) {
        self.threads = threads
        self.turns = turns
    }

    func listThreads(limit: Int) async throws -> [CodexThreadRecord] {
        requestedLimits.append(limit)
        return threads
    }

    func recentTurns(threadID: String, turnLimit: Int) async throws -> [CodexTurnRecord] {
        Array(turns.prefix(turnLimit))
    }

    func continueThread(id threadID: String, requestID: String) async throws {}

    func respondToPlan(
        id threadID: String,
        plan: String,
        model: String,
        action: CodexTaskAction,
        requestID: String
    ) async throws {
        planActions.append(action)
    }
}

@Test func unavailableCodexDoesNotBlockIndependentBoardSnapshotData() async throws {
    let source = CodexHistoryTaskSource(client: UnavailableCodexAppServer())
    let snapshot = try await source.snapshot(revision: 9)

    #expect(snapshot.revision == 9)
    #expect(snapshot.codexEnabled)
    #expect(snapshot.tasks.isEmpty)
    #expect(snapshot.capabilities.contains("macPower.read"))
    #expect(snapshot.capabilities.contains("hostTime.read"))
}

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

@Test func recentCodexChatKeepsOnlyNewestVisibleUserAndAssistantText() throws {
    let data = Data(#"""
    [
      {
        "items": [
          {"id":"new-user","type":"userMessage","content":[{"type":"text","text":"Newest question"},{"type":"image","url":"data:image/png;base64,private"}]},
          {"id":"tool","type":"commandExecution","command":"cat secret","cwd":"/private/project","commandActions":[],"status":"completed"},
          {"id":"new-agent","type":"agentMessage","text":"Newest answer","phase":"final_answer"}
        ]
      },
      {
        "items": [
          {"id":"old-user","type":"userMessage","content":[{"type":"text","text":"Older question"}]},
          {"id":"reasoning","type":"reasoning","summary":["private reasoning"]},
          {"id":"old-agent","type":"agentMessage","text":"Older answer","phase":"commentary"}
        ]
      }
    ]
    """#.utf8)
    let newestFirst = try JSONDecoder().decode([CodexTurnRecord].self, from: data)
    let messages = CodexChatHistoryMapper.messages(fromNewestFirst: newestFirst)

    #expect(messages == [
        CodexChatMessage(role: .user, text: "Older question"),
        CodexChatMessage(role: .assistant, text: "Older answer"),
        CodexChatMessage(role: .user, text: "Newest question"),
        CodexChatMessage(role: .assistant, text: "Newest answer"),
    ])
    #expect(!messages.contains { $0.text.contains("secret") || $0.text.contains("reasoning") })
}

@Test func latestCompletedPlanOffersOnlyApproveAndRejectWithConsent() throws {
    let thread = CodexThreadRecord(
        id: "plan",
        name: "Review this plan",
        updatedAt: 1,
        status: CodexThreadStatus(type: "idle", activeFlags: nil)
    )
    let turns = try JSONDecoder().decode([CodexTurnRecord].self, from: Data(#"""
    [{"status":"completed","model":"gpt-5.6","items":[
      {"id":"plan-item","type":"plan","text":"1. Make the bounded change\n2. Verify it"}
    ]}]
    """#.utf8))

    #expect(CodexPlanPolicy.availableActions(
        thread: thread,
        newestFirst: turns,
        consentEnabled: true
    ) == [.approvePlan, .rejectPlan])
    #expect(CodexPlanPolicy.availableActions(
        thread: thread,
        newestFirst: turns,
        consentEnabled: false
    ).isEmpty)
    #expect(CodexPlanPolicy.responseContext(thread: thread, newestFirst: turns) == CodexPlanResponseContext(
        text: "1. Make the bounded change\n2. Verify it",
        model: "gpt-5.6"
    ))
}

@Test func staleOrIncompletePlanCannotBeActioned() throws {
    let thread = CodexThreadRecord(
        id: "plan",
        name: "Review this plan",
        updatedAt: 1,
        status: CodexThreadStatus(type: "idle", activeFlags: nil)
    )
    let turns = try JSONDecoder().decode([CodexTurnRecord].self, from: Data(#"""
    [
      {"status":"completed","model":"gpt-5.6","items":[{"type":"agentMessage","text":"Newer final answer"}]},
      {"status":"completed","model":"gpt-5.6","items":[{"type":"plan","text":"Old plan"}]}
    ]
    """#.utf8))
    #expect(CodexPlanPolicy.responseContext(thread: thread, newestFirst: turns) == nil)
}

@Test func planResponsesUseExplicitCollaborationModesAndFixedText() throws {
    let approve = CodexPlanTurnRequestBuilder.parameters(
        threadID: "plan-task",
        plan: "1. Implement safely",
        model: "gpt-5.6",
        action: .approvePlan,
        requestID: "approve-1"
    )
    let reject = CodexPlanTurnRequestBuilder.parameters(
        threadID: "plan-task",
        plan: "must not be sent on reject",
        model: "gpt-5.6",
        action: .rejectPlan,
        requestID: "reject-1"
    )
    let approveMode = try #require(approve["collaborationMode"] as? [String: Any])
    let rejectMode = try #require(reject["collaborationMode"] as? [String: Any])
    let approveInput = try #require(approve["input"] as? [[String: String]])
    let rejectInput = try #require(reject["input"] as? [[String: String]])

    #expect(approveMode["mode"] as? String == "default")
    #expect(rejectMode["mode"] as? String == "plan")
    #expect(approveInput.first?["text"] == "PLEASE IMPLEMENT THIS PLAN:\n\n1. Implement safely")
    #expect(rejectInput.first?["text"] == "Please revise the proposed plan before implementation.")
}

@Test func taskSourceRequestsAndReturnsTenMostRecentThreads() async throws {
    let threads = (0..<12).map { index in
        CodexThreadRecord(
            id: "task-\(index)",
            name: "Task \(index)",
            updatedAt: Int64(100 - index),
            status: CodexThreadStatus(type: "idle", activeFlags: nil)
        )
    }
    let client = RecordingCodexAppServer(threads: threads)
    let source = CodexHistoryTaskSource(client: client)
    let snapshot = try await source.snapshot(revision: 1)

    #expect(snapshot.tasks.count == codexTaskMaximumCount)
    #expect(snapshot.tasks.first?.id == "task-0")
    #expect(snapshot.tasks.last?.id == "task-9")
    #expect(await client.requestedLimits == [codexTaskMaximumCount])
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
    defaults.set(true, forKey: "ilo-board.codex-fixed-continue.v1")
    let controller = CodexContinueFeatureController(defaults: defaults)
    #expect(!controller.isEnabled)
    controller.setEnabled(true)
    #expect(controller.isEnabled)
    controller.setEnabled(false)
    #expect(!controller.isEnabled)
}

@Test func planActionIsRevalidatedBeforeTheClientReceivesIt() async throws {
    let suite = "CodexPlanActionTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let consent = CodexContinueFeatureController(defaults: defaults)
    consent.setEnabled(true)
    let thread = CodexThreadRecord(
        id: "plan-task",
        name: "Plan task",
        updatedAt: 1,
        status: CodexThreadStatus(type: "idle", activeFlags: nil)
    )
    let turns = try JSONDecoder().decode([CodexTurnRecord].self, from: Data(#"""
    [{"status":"completed","model":"gpt-5.6","items":[{"type":"plan","text":"Safe plan"}]}]
    """#.utf8))
    let client = RecordingCodexAppServer(threads: [thread], turns: turns)
    let source = CodexHistoryTaskSource(continueFeature: consent, client: client)

    let outcome = await source.performCodexAction(
        id: thread.id,
        action: .approvePlan,
        requestID: "board-plan-safe"
    )
    guard case .accepted = outcome else {
        Issue.record("A current completed plan should be accepted")
        return
    }
    #expect(await client.planActions == [.approvePlan])
}
