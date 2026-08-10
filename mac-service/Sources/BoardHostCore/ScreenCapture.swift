import BoardProtocol
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

public enum ScreenCaptureError: Error, Equatable, LocalizedError, Sendable {
    case connectionClosed
    case duplicateBegin
    case invalidMetadata
    case invalidRequestID
    case invalidSequence
    case invalidChunk
    case incomplete
    case boardRejected(code: String, message: String)
    case checksumMismatch
    case pngEncodingFailed
    case hostUnavailable(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .connectionClosed: "The board disconnected before capture completed."
        case .duplicateBegin: "The board sent more than one capture header."
        case .invalidMetadata: "The board returned invalid capture metadata."
        case .invalidRequestID: "The capture response does not match this request."
        case .invalidSequence: "A capture chunk was missing, duplicated, or out of order."
        case .invalidChunk: "A capture chunk has an invalid offset or size."
        case .incomplete: "The capture ended before every pixel arrived."
        case let .boardRejected(code, message): "The board rejected capture (\(code)): \(message)"
        case .checksumMismatch: "The capture checksum does not match the received pixels."
        case .pngEncodingFailed: "The RGB565 framebuffer could not be encoded as PNG."
        case let .hostUnavailable(message): "The capture host could not start: \(message)"
        case .timedOut: "Timed out waiting for the paired board."
        }
    }
}

public struct CapturedScreen: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgb565LittleEndian: Data

    public init(width: Int, height: Int, rgb565LittleEndian: Data) {
        self.width = width
        self.height = height
        self.rgb565LittleEndian = rgb565LittleEndian
    }
}

public struct ScreenCaptureAssembler: Sendable {
    private let requestID: String
    private var metadata: ScreenCaptureBeginMessage?
    private var pixels = Data()
    private var nextSequence = 0

    public init(requestID: String) {
        self.requestID = requestID
    }

    public mutating func begin(_ message: ScreenCaptureBeginMessage) throws {
        guard metadata == nil else { throw ScreenCaptureError.duplicateBegin }
        guard message.requestID == requestID else { throw ScreenCaptureError.invalidRequestID }
        guard message.type == "screenCaptureBegin",
              message.version == screenCaptureProtocolVersion,
              message.format == "rgb565le",
              message.width == screenCaptureWidth,
              message.height == screenCaptureHeight,
              message.totalBytes == screenCaptureRGB565Bytes,
              message.chunkBytes == screenCaptureMaximumChunkBytes,
              message.chunkCount == screenCaptureChunkCount
        else {
            throw ScreenCaptureError.invalidMetadata
        }
        metadata = message
        pixels.reserveCapacity(message.totalBytes)
    }

    public mutating func append(_ message: ScreenCaptureChunkMessage) throws {
        guard message.requestID == requestID else { throw ScreenCaptureError.invalidRequestID }
        guard let metadata else { throw ScreenCaptureError.invalidSequence }
        guard message.type == "screenCaptureChunk",
              message.version == screenCaptureProtocolVersion,
              message.sequence == nextSequence
        else {
            throw ScreenCaptureError.invalidSequence
        }
        let remaining = metadata.totalBytes - pixels.count
        let expectedSize = min(metadata.chunkBytes, remaining)
        guard remaining > 0,
              message.offset == pixels.count,
              message.data.count == expectedSize
        else {
            throw ScreenCaptureError.invalidChunk
        }
        pixels.append(message.data)
        nextSequence += 1
    }

    public mutating func finish(_ message: ScreenCaptureResultMessage) throws -> CapturedScreen {
        guard message.requestID == requestID else { throw ScreenCaptureError.invalidRequestID }
        guard message.type == "screenCaptureResult", message.version == screenCaptureProtocolVersion else {
            throw ScreenCaptureError.invalidMetadata
        }
        guard message.status == "ok" || message.status == "error" else {
            throw ScreenCaptureError.invalidMetadata
        }
        if message.status == "error" {
            guard message.totalBytes == nil,
                  message.sha256 == nil,
                  let code = message.errorCode,
                  !code.isEmpty,
                  code.utf8.count <= 64,
                  let detail = message.message,
                  !detail.isEmpty,
                  detail.utf8.count <= 160
            else {
                throw ScreenCaptureError.invalidMetadata
            }
            throw ScreenCaptureError.boardRejected(
                code: code,
                message: detail
            )
        }
        guard let metadata,
              pixels.count == metadata.totalBytes,
              nextSequence == metadata.chunkCount,
              message.totalBytes == metadata.totalBytes,
              message.errorCode == nil,
              message.message == nil,
              let expectedDigest = message.sha256,
              expectedDigest.utf8.count == 64,
              expectedDigest.utf8.allSatisfy({
                  ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
              })
        else {
            throw ScreenCaptureError.incomplete
        }
        let actualDigest = SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined()
        guard expectedDigest == actualDigest else { throw ScreenCaptureError.checksumMismatch }
        return CapturedScreen(width: metadata.width, height: metadata.height, rgb565LittleEndian: pixels)
    }
}

public enum ScreenCapturePNGEncoder {
    public static func encode(_ capture: CapturedScreen) throws -> Data {
        guard capture.width == screenCaptureWidth,
              capture.height == screenCaptureHeight,
              capture.rgb565LittleEndian.count == screenCaptureRGB565Bytes
        else {
            throw ScreenCaptureError.invalidMetadata
        }

        var rgba = Data(count: capture.width * capture.height * 4)
        rgba.withUnsafeMutableBytes { destination in
            capture.rgb565LittleEndian.withUnsafeBytes { source in
                let input = source.bindMemory(to: UInt8.self)
                let output = destination.bindMemory(to: UInt8.self)
                for pixel in 0..<(capture.width * capture.height) {
                    let packed = UInt16(input[pixel * 2]) | (UInt16(input[pixel * 2 + 1]) << 8)
                    let red5 = UInt8((packed >> 11) & 0x1f)
                    let green6 = UInt8((packed >> 5) & 0x3f)
                    let blue5 = UInt8(packed & 0x1f)
                    output[pixel * 4] = (red5 << 3) | (red5 >> 2)
                    output[pixel * 4 + 1] = (green6 << 2) | (green6 >> 4)
                    output[pixel * 4 + 2] = (blue5 << 3) | (blue5 >> 2)
                    output[pixel * 4 + 3] = 255
                }
            }
        }

        guard let provider = CGDataProvider(data: rgba as CFData),
              let image = CGImage(
                width: capture.width,
                height: capture.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: capture.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)],
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            throw ScreenCaptureError.pngEncodingFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw ScreenCaptureError.pngEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenCaptureError.pngEncodingFailed }
        return output as Data
    }
}
