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

