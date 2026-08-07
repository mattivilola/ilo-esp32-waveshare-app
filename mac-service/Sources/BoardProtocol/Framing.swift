import Foundation

public enum FrameError: Error, Equatable, Sendable {
    case empty
    case tooLarge(Int)
}

public enum FrameEncoder {
    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else { throw FrameError.empty }
        guard payload.count <= boardProtocolMaximumFrameBytes else {
            throw FrameError.tooLarge(payload.count)
        }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        return frame
    }
}

public struct FrameDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let count = Int(length)
            guard count > 0 else { throw FrameError.empty }
            guard count <= boardProtocolMaximumFrameBytes else { throw FrameError.tooLarge(count) }
            guard buffer.count >= count + 4 else { break }
            frames.append(buffer.subdata(in: 4..<(count + 4)))
            buffer.removeSubrange(0..<(count + 4))
        }
        return frames
    }
}

