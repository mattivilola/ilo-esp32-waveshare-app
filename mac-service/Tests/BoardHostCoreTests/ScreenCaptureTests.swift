import BoardHostCore
import BoardProtocol
import CryptoKit
import Foundation
import ImageIO
import Testing

private func beginMessage(chunkBytes: Int = screenCaptureMaximumChunkBytes) -> ScreenCaptureBeginMessage {
    ScreenCaptureBeginMessage(
        type: "screenCaptureBegin",
        version: screenCaptureProtocolVersion,
        requestID: "capture-test",
        format: "rgb565le",
        width: screenCaptureWidth,
        height: screenCaptureHeight,
        totalBytes: screenCaptureRGB565Bytes,
        chunkBytes: chunkBytes,
        chunkCount: (screenCaptureRGB565Bytes + chunkBytes - 1) / chunkBytes
    )
}

@Test func assemblesStrictlySequencedCapture() throws {
    let pixels = Data(repeating: 0x5a, count: screenCaptureRGB565Bytes)
    var assembler = ScreenCaptureAssembler(requestID: "capture-test")
    let header = beginMessage()
    try assembler.begin(header)
    for sequence in 0..<header.chunkCount {
        let offset = sequence * header.chunkBytes
        let end = min(offset + header.chunkBytes, pixels.count)
        try assembler.append(ScreenCaptureChunkMessage(
            type: "screenCaptureChunk",
            version: screenCaptureProtocolVersion,
            requestID: "capture-test",
            sequence: sequence,
            offset: offset,
            data: pixels.subdata(in: offset..<end)
        ))
    }
    let digest = SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined()
    let capture = try assembler.finish(ScreenCaptureResultMessage(
        type: "screenCaptureResult",
        version: screenCaptureProtocolVersion,
        requestID: "capture-test",
        status: "ok",
        totalBytes: pixels.count,
        sha256: digest,
        errorCode: nil,
        message: nil
    ))
    #expect(capture.rgb565LittleEndian == pixels)
}

@Test func rejectsOutOfOrderAndMismatchedCaptureData() throws {
    var assembler = ScreenCaptureAssembler(requestID: "capture-test")
    try assembler.begin(beginMessage())
    #expect(throws: ScreenCaptureError.invalidSequence) {
        try assembler.append(ScreenCaptureChunkMessage(
            type: "screenCaptureChunk",
            version: screenCaptureProtocolVersion,
            requestID: "capture-test",
            sequence: 1,
            offset: 0,
            data: Data(repeating: 0, count: screenCaptureMaximumChunkBytes)
        ))
    }
}

@Test func rejectsUnsafeCaptureMetadataAndOffsets() throws {
    var metadataAssembler = ScreenCaptureAssembler(requestID: "capture-test")
    #expect(throws: ScreenCaptureError.invalidMetadata) {
        try metadataAssembler.begin(ScreenCaptureBeginMessage(
            type: "screenCaptureBegin",
            version: screenCaptureProtocolVersion,
            requestID: "capture-test",
            format: "rgb565le",
            width: 800,
            height: 480,
            totalBytes: 768_000,
            chunkBytes: screenCaptureMaximumChunkBytes,
            chunkCount: 32
        ))
    }

    var chunkSizeAssembler = ScreenCaptureAssembler(requestID: "capture-test")
    #expect(throws: ScreenCaptureError.invalidMetadata) {
        try chunkSizeAssembler.begin(beginMessage(chunkBytes: 6_144))
    }

    var chunkAssembler = ScreenCaptureAssembler(requestID: "capture-test")
    try chunkAssembler.begin(beginMessage())
    #expect(throws: ScreenCaptureError.invalidChunk) {
        try chunkAssembler.append(ScreenCaptureChunkMessage(
            type: "screenCaptureChunk",
            version: screenCaptureProtocolVersion,
            requestID: "capture-test",
            sequence: 0,
            offset: 1,
            data: Data(repeating: 0, count: screenCaptureMaximumChunkBytes)
        ))
    }
}

@Test func maximumCaptureChunkFitsBoundedFrame() throws {
    let message = ScreenCaptureChunkMessage(
        type: "screenCaptureChunk",
        version: screenCaptureProtocolVersion,
        requestID: "12345678-1234-1234-1234-123456789012",
        sequence: 49,
        offset: screenCaptureRGB565Bytes - screenCaptureMaximumChunkBytes,
        data: Data(repeating: 0xff, count: screenCaptureMaximumChunkBytes)
    )
    let payload = try ProtocolJSON.encoder().encode(message)
    let boardBase64Bytes = ((screenCaptureMaximumChunkBytes + 2) / 3) * 4
    #expect(boardBase64Bytes + 256 <= 4_096)
    #expect(payload.count < boardProtocolMaximumFrameBytes)
    #expect(throws: Never.self) { try FrameEncoder.encode(payload) }
}

@Test func convertsRGB565LittleEndianToPNG() throws {
    var pixels = Data(count: screenCaptureRGB565Bytes)
    pixels[0] = 0x00
    pixels[1] = 0xf8
    let png = try ScreenCapturePNGEncoder.encode(CapturedScreen(
        width: screenCaptureWidth,
        height: screenCaptureHeight,
        rgb565LittleEndian: pixels
    ))
    #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    let source = CGImageSourceCreateWithData(png as CFData, nil)
    let image = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    #expect(image?.width == screenCaptureWidth)
    #expect(image?.height == screenCaptureHeight)
    var decoded = [UInt8](repeating: 0, count: 4)
    decoded.withUnsafeMutableBytes { bytes in
        let context = CGContext(
            data: bytes.baseAddress,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )
        if let firstPixel = image?.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) {
            context?.draw(firstPixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
    #expect(decoded == [255, 0, 0, 255])
}
