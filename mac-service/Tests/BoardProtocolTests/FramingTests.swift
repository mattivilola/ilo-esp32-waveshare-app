import BoardProtocol
import Foundation
import Testing

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

    #expect(snapshot.capabilities == ["tasks.read", "macPower.read"])
    #expect(snapshot.macPower?.levelPercent == 100)
    #expect(encodedPower.keys.sorted() == ["levelPercent", "state"])
    #expect(encodedPower["levelPercent"] as? Int == 100)
    #expect(encodedPower["state"] as? String == "charging")
}
