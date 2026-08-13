import BoardProtocol
import Foundation
import Testing

@Test func focusCompletionProtocolRoundTripsBoundedReceipt() throws {
    let message = FocusCompletionMessage(
        eventID: "focus-1770000000",
        durationMinutes: 25,
        completedEpoch: 1_770_000_000
    )
    let payload = try ProtocolJSON.encoder().encode(message)
    let decoded = try ProtocolJSON.decoder().decode(FocusCompletionMessage.self, from: payload)
    #expect(decoded == message)
    #expect(FocusCompletionAcknowledgement(eventID: message.eventID).type == "focusCompletionAck")
}

@Test func frameDecoderHandlesPartialAndCoalescedFrames() throws {
    let first = try FrameEncoder.encode(Data("first".utf8))
    let second = try FrameEncoder.encode(Data("second".utf8))
    var decoder = FrameDecoder()

    #expect(try decoder.append(first.prefix(3)).isEmpty)
    let combined = first.dropFirst(3) + second
    let frames = try decoder.append(Data(combined))
    #expect(frames == [Data("first".utf8), Data("second".utf8)])
}

@Test func frameEncoderRejectsUnsafeSizes() throws {
    #expect(throws: FrameError.empty) { try FrameEncoder.encode(Data()) }
    #expect(throws: FrameError.tooLarge(boardProtocolMaximumFrameBytes + 1)) {
        try FrameEncoder.encode(Data(repeating: 0, count: boardProtocolMaximumFrameBytes + 1))
    }
}

@Test func macPowerSnapshotContainsOnlyPercentageAndCoarseState() throws {
    let power = MacPowerStatus(levelPercent: 140, state: .charging)
    let snapshot = DashboardSnapshot(revision: 8, tasks: [], macPower: power)
    let data = try ProtocolJSON.encoder().encode(snapshot)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let encodedPower = try #require(object["macPower"] as? [String: Any])

    #expect(snapshot.capabilities == ["tasks.read", "tasks.chat.read", "macPower.read", "hostTime.read"])
    #expect(snapshot.codexEnabled == true)
    #expect(snapshot.xNewsEnabled == false)
    #expect(object["codexEnabled"] as? Bool == true)
    #expect(object["xNewsEnabled"] as? Bool == false)
    #expect(snapshot.macPower?.levelPercent == 100)
    #expect(encodedPower.keys.sorted() == ["levelPercent", "state"])
    #expect(encodedPower["levelPercent"] as? Int == 100)
    #expect(encodedPower["state"] as? String == "charging")
}

@Test func codexChatMessagesAreReadOnlyAndBounded() throws {
    let request = CodexChatRequest(requestID: "board-chat-1", taskID: "019f-task-7")
    let requestData = try ProtocolJSON.encoder().encode(request)
    let requestObject = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
    #expect(requestObject.keys.sorted() == ["requestID", "taskID", "type", "version"])
    #expect(requestObject["type"] as? String == "codexChatRequest")
    #expect(requestObject["action"] == nil)

    let response = CodexChatDetailMessage(
        requestID: "board-chat-1",
        taskID: "019f-task-7",
        status: .ready,
        title: "Board chat detail",
        messages: (0..<8).map { index in
            CodexChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant, text: "Message \(index)")
        }
    )
    #expect(response.messages.count == codexChatMaximumMessages)
    let decoded = try ProtocolJSON.decoder().decode(
        CodexChatDetailMessage.self,
        from: ProtocolJSON.encoder().encode(response)
    )
    #expect(decoded == response)
}

@Test func fixedCodexContinueCapabilityRequiresMacOptIn() {
    let disabled = DashboardSnapshot(revision: 1, tasks: [])
    let enabled = DashboardSnapshot(revision: 2, tasks: [], codexContinueEnabled: true)
    #expect(!disabled.capabilities.contains("tasks.continue.fixed"))
    #expect(enabled.capabilities.contains("tasks.continue.fixed"))
}

@Test func disabledCodexScreenOmitsTaskDataAndCapabilities() throws {
    let task = TaskCard(
        id: "private-task",
        title: "Should not cross the wire",
        state: .active,
        attentionKind: .none,
        updatedAt: Date(),
        shortSummary: "Hidden with the optional screen"
    )
    let snapshot = DashboardSnapshot(
        revision: 3,
        tasks: [task],
        codexEnabled: false,
        codexContinueEnabled: true
    )

    #expect(snapshot.codexEnabled == false)
    #expect(snapshot.tasks.isEmpty)
    #expect(!snapshot.capabilities.contains("tasks.read"))
    #expect(!snapshot.capabilities.contains("tasks.chat.read"))
    #expect(!snapshot.capabilities.contains("tasks.continue.fixed"))
}

@Test func codexContinueMessagesCarryOnlyFixedBoundedActionData() throws {
    let request = CodexContinueRequest(requestID: "board-A12", taskID: "019f-task-7")
    let requestData = try ProtocolJSON.encoder().encode(request)
    let requestObject = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
    #expect(requestObject.keys.sorted() == ["action", "requestID", "taskID", "type", "version"])
    #expect(requestObject["type"] as? String == "codexContinueRequest")
    #expect(requestObject["action"] as? String == "continue")
    #expect(requestObject["taskID"] as? String == "019f-task-7")
    #expect(requestObject["version"] as? Int == 1)

    let response = CodexContinueStatusMessage(
        requestID: "board-A12",
        status: .accepted,
        message: "Please continue was sent"
    )
    let decoded = try ProtocolJSON.decoder().decode(
        CodexContinueStatusMessage.self,
        from: ProtocolJSON.encoder().encode(response)
    )
    #expect(decoded == response)
}

@Test func hostTimeSnapshotContainsOnlyBoundedTimezoneInformation() throws {
    let helsinki = try #require(TimeZone(identifier: "Europe/Helsinki"))
    let summer = HostTimeStatus(
        date: Date(timeIntervalSince1970: 1_788_000_000),
        timeZone: helsinki
    )
    let winter = HostTimeStatus(
        date: try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")),
        timeZone: helsinki
    )
    let snapshot = DashboardSnapshot(revision: 9, tasks: [], hostTime: summer)
    let data = try ProtocolJSON.encoder().encode(snapshot)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let encoded = try #require(object["hostTime"] as? [String: Any])

    #expect(encoded.keys.sorted() == ["timezoneAbbreviation", "utcOffsetSeconds"])
    #expect(encoded["utcOffsetSeconds"] as? Int == 10_800)
    #expect(encoded["timezoneAbbreviation"] as? String == "EEST")
    #expect(winter.utcOffsetSeconds == 7_200)
    #expect(winter.timezoneAbbreviation == "EET")
}

@Test func legacySnapshotWithoutHostTimeRemainsCompatible() throws {
    let data = Data("""
    {
        "protocolVersion":1,
        "revision":1,
        "generatedAt":"2026-01-15T12:00:00Z",
        "hostState":"online",
        "capabilities":["tasks.read"],
        "tasks":[]
    }
    """.utf8)

    let snapshot = try ProtocolJSON.decoder().decode(DashboardSnapshot.self, from: data)
    #expect(snapshot.hostTime == nil)
}

@Test func weatherLocationIsRoundedAndBoundedBeforeTransport() {
    let location = WeatherLocation(
        name: String(repeating: "L", count: 60) + " 📍",
        latitude: 60.1699,
        longitude: 24.9384
    )
    #expect(location.name.count == 40)
    #expect(location.latitude == 60.17)
    #expect(location.longitude == 24.94)
}

@Test func weatherLocationUsesAReadableBoardSafeCityName() {
    let location = WeatherLocation(name: "Järvenpää 📍", latitude: 60.47, longitude: 25.09)
    #expect(location.name == "Jarvenpaa")
    #expect(location.name.unicodeScalars.allSatisfy { $0.isASCII })
}

@Test func softwareVersionsAreOptionalProtocolV1Metadata() throws {
    let snapshot = DashboardSnapshot(
        revision: 10,
        tasks: [],
        companionVersion: "0.1.3"
    )
    let snapshotData = try ProtocolJSON.encoder().encode(snapshot)
    let snapshotObject = try #require(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
    #expect(snapshotObject["companionVersion"] as? String == "0.1.3")

    let hello = ClientMessage(
        type: "hello",
        protocolVersion: 1,
        boardID: "ilo-board-test",
        firmwareVersion: "0.2.0"
    )
    let decoded = try ProtocolJSON.decoder().decode(
        ClientMessage.self,
        from: ProtocolJSON.encoder().encode(hello)
    )
    #expect(decoded.firmwareVersion == "0.2.0")

    let legacyHello = Data(#"{"type":"hello","protocolVersion":1,"boardID":"legacy"}"#.utf8)
    #expect(try ProtocolJSON.decoder().decode(ClientMessage.self, from: legacyHello).firmwareVersion == nil)
}

@Test func legacySnapshotInfersXNewsVisibilityFromItsFeed() throws {
    let feed = NewsFeedSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        stories: []
    )

    for (snapshot, expected) in [
        (DashboardSnapshot(revision: 1, tasks: []), false),
        (DashboardSnapshot(revision: 2, tasks: [], newsFeed: feed), true),
    ] {
        let encoded = try ProtocolJSON.encoder().encode(snapshot)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "xNewsEnabled")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try ProtocolJSON.decoder().decode(DashboardSnapshot.self, from: legacyData)
        #expect(decoded.xNewsEnabled == expected)
    }
}

@Test func legacySnapshotInfersCodexVisibilityFromTaskCapability() throws {
    let encoded = try ProtocolJSON.encoder().encode(DashboardSnapshot(revision: 1, tasks: []))
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "codexEnabled")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try ProtocolJSON.decoder().decode(DashboardSnapshot.self, from: legacyData)
    #expect(decoded.codexEnabled == true)
}

@Test func xNewsRefreshMessagesStayBoundedAndExplicit() throws {
    let request = XNewsRefreshRequest(requestID: "board-1234")
    let requestData = try ProtocolJSON.encoder().encode(request)
    let requestObject = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: String])
    #expect(requestObject == ["type": "xNewsRefreshRequest", "requestID": "board-1234"])

    let status = XNewsRefreshStatusMessage(
        requestID: "board-1234",
        status: .cooldown,
        message: "Refresh available after the 15 minute cooldown"
    )
    let decoded = try ProtocolJSON.decoder().decode(
        XNewsRefreshStatusMessage.self,
        from: ProtocolJSON.encoder().encode(status)
    )
    #expect(decoded == status)
}

@Test func firmwareUpdateMessagesUseOnlyFixedActionsAndBoundedStatus() throws {
    let command = FirmwareUpdateCommand(action: .install)
    let commandData = try ProtocolJSON.encoder().encode(command)
    let commandObject = try #require(JSONSerialization.jsonObject(with: commandData) as? [String: Any])
    #expect(commandObject["type"] as? String == "firmwareUpdateCommand")
    #expect(commandObject["action"] as? String == "install")
    #expect(commandObject["url"] == nil)
    #expect(try ProtocolJSON.decoder().decode(FirmwareUpdateCommand.self, from: commandData) == command)

    let status = FirmwareUpdateStatusMessage(
        state: .downloading,
        currentVersion: "0.2.0",
        availableVersion: "0.2.1",
        progressPercent: 62,
        message: "Downloading signed firmware"
    )
    #expect(
        try ProtocolJSON.decoder().decode(
            FirmwareUpdateStatusMessage.self,
            from: ProtocolJSON.encoder().encode(status)
        ) == status
    )
}
