import BoardProtocol
import CryptoKit
import Darwin
import Foundation
import Security

enum USBSessionCryptography {
    static let prefix = "~ILOUSB1"
    static let info = Data("ILO Board USB v1".utf8)

    static func authenticationCode(
        label: String,
        secret: Data,
        clientNonce: Data,
        boardNonce: Data,
        boardID: String
    ) -> Data {
        var payload = Data("ILOUSB1 \(label)".utf8)
        payload.append(clientNonce)
        payload.append(boardNonce)
        payload.append(Data(boardID.utf8))
        return Data(HMAC<SHA256>.authenticationCode(
            for: payload,
            using: SymmetricKey(data: secret)
        ))
    }

    static func sessionKey(secret: Data, clientNonce: Data, boardNonce: Data) -> SymmetricKey {
        var salt = clientNonce
        salt.append(boardNonce)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    static func seal(_ plaintext: Data, key: SymmetricKey, direction: Character, sequence: UInt64) throws -> Data {
        let nonce = try ChaChaPoly.Nonce(data: nonceData(direction: direction, sequence: sequence))
        let box = try ChaChaPoly.seal(
            plaintext,
            using: key,
            nonce: nonce,
            authenticating: additionalData(direction: direction, sequence: sequence)
        )
        return box.combined
    }

    static func open(
        _ combined: Data,
        key: SymmetricKey,
        direction: Character,
        sequence: UInt64
    ) throws -> Data {
        guard combined.count >= 28,
              combined.prefix(12) == nonceData(direction: direction, sequence: sequence)
        else { throw USBSerialChannelError.invalidEncryptedFrame }
        let box = try ChaChaPoly.SealedBox(combined: combined)
        return try ChaChaPoly.open(
            box,
            using: key,
            authenticating: additionalData(direction: direction, sequence: sequence)
        )
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func data(hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else { return nil }
            bytes.append(byte)
            index = end
        }
        return Data(bytes)
    }

    private static func nonceData(direction: Character, sequence: UInt64) -> Data {
        var result = Data(direction == "M" ? [0x4D, 0x41, 0x43, 0x00] : [0x42, 0x52, 0x44, 0x00])
        var bigEndian = sequence.bigEndian
        withUnsafeBytes(of: &bigEndian) { result.append(contentsOf: $0) }
        return result
    }

    private static func additionalData(direction: Character, sequence: UInt64) -> Data {
        Data("ILOUSB1|\(direction)|\(sequence)".utf8)
    }
}

enum USBSerialChannelError: Error, LocalizedError {
    case cannotOpen
    case cannotConfigure
    case handshakeTimedOut
    case invalidHandshake
    case challengeAuthenticationFailed
    case authenticationResponseRejected
    case invalidEncryptedFrame
    case inputTooLarge
    case disconnected

    var errorDescription: String? {
        switch self {
        case .cannotOpen: "The USB serial port could not be opened. It may be in use by a flashing or monitor tool."
        case .cannotConfigure: "The USB serial port could not be configured."
        case .handshakeTimedOut: "The connected firmware did not offer ILO Board USB fallback."
        case .invalidHandshake: "The USB fallback handshake was malformed."
        case .challengeAuthenticationFailed: "The USB challenge did not match the paired board credential."
        case .authenticationResponseRejected: "The board rejected the Mac USB authentication response."
        case .invalidEncryptedFrame: "The USB fallback frame failed authenticated decryption."
        case .inputTooLarge: "The USB fallback frame exceeded the protocol limit."
        case .disconnected: "The USB serial connection closed."
        }
    }
}

final class USBSerialBoardConnectionChannel: BoardConnectionChannel, @unchecked Sendable {
    private static let maximumLineBytes = 90_000
    // Protocol v1 waits up to five seconds for AUTH after issuing a challenge.
    // Never place a second HELLO inside that window: older installed firmware
    // would correctly reject it as a malformed AUTH. Spaced attempts also span
    // native USB re-enumeration during a board boot.
    static let challengeAttemptMilliseconds: Int32 = 6_000
    static let challengeAttemptCount = 3
    private let path: String
    private let boardID: String
    private let secret: Data
    private let serialQueue = DispatchQueue(label: "com.iloapps.iloboard.host.usb")
    private let stateLock = NSLock()
    private var descriptor: Int32 = -1
    private var running = false
    private var didClose = false
    private var incomingBuffer = Data()
    private var outgoingFrames: [Data] = []
    private var eventQueue: DispatchQueue?
    private var eventHandler: (@Sendable (BoardConnectionChannelEvent) -> Void)?
    private var key: SymmetricKey?
    private var sendSequence: UInt64 = 0
    private var receiveSequence: UInt64 = 0

    init(path: String, boardID: String, secret: Data) {
        self.path = path
        self.boardID = boardID
        self.secret = secret
    }

    func start(
        queue: DispatchQueue,
        eventHandler: @escaping @Sendable (BoardConnectionChannelEvent) -> Void
    ) {
        stateLock.withLock {
            eventQueue = queue
            self.eventHandler = eventHandler
            running = true
        }
        serialQueue.async { [weak self] in self?.run() }
    }

    func send(_ data: Data) {
        stateLock.withLock {
            guard running else { return }
            outgoingFrames.append(data)
        }
    }

    func cancel() {
        let fileDescriptor = stateLock.withLock { () -> Int32 in
            running = false
            let openDescriptor = descriptor
            descriptor = -1
            return openDescriptor
        }
        if fileDescriptor >= 0 { Darwin.close(fileDescriptor) }
    }

    private func run() {
        defer { finish(nil) }
        do {
            let fileDescriptor = try openAndConfigure()
            let shouldContinue = stateLock.withLock { () -> Bool in
                guard running else { return false }
                descriptor = fileDescriptor
                return true
            }
            guard shouldContinue else {
                Darwin.close(fileDescriptor)
                finish(nil)
                return
            }
            try handshake(fileDescriptor)
            emit(.ready)
            while isRunning {
                try sendPendingFrames(fileDescriptor)
                if let line = try readLine(fileDescriptor, timeoutMilliseconds: 100) {
                    if line.hasPrefix("\(USBSessionCryptography.prefix) DATA B ") {
                        try handleEncryptedLine(line)
                    }
                }
            }
        } catch {
            finish(error.localizedDescription)
        }
    }

    private var isRunning: Bool {
        stateLock.withLock { running }
    }

    private func openAndConfigure() throws -> Int32 {
        let fileDescriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fileDescriptor >= 0 else { throw USBSerialChannelError.cannotOpen }
        guard ioctl(fileDescriptor, TIOCEXCL) == 0 else {
            Darwin.close(fileDescriptor)
            throw USBSerialChannelError.cannotOpen
        }
        var options = termios()
        guard tcgetattr(fileDescriptor, &options) == 0 else {
            Darwin.close(fileDescriptor)
            throw USBSerialChannelError.cannotConfigure
        }
        cfmakeraw(&options)
        _ = cfsetspeed(&options, speed_t(B115200))
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        guard tcsetattr(fileDescriptor, TCSANOW, &options) == 0,
              fcntl(fileDescriptor, F_SETFL, 0) == 0
        else {
            Darwin.close(fileDescriptor)
            throw USBSerialChannelError.cannotConfigure
        }
        tcflush(fileDescriptor, TCIOFLUSH)
        return fileDescriptor
    }

    private func handshake(_ fileDescriptor: Int32) throws {
        var clientNonce = Data(count: 32)
        let randomStatus = clientNonce.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw USBSerialChannelError.challengeAuthenticationFailed
        }
        let hello = "\(USBSessionCryptography.prefix) HELLO \(USBSessionCryptography.hex(clientNonce))"
        var boardNonce: Data?
        var sawAuthenticatedMismatch = false
        for _ in 0..<Self.challengeAttemptCount where boardNonce == nil && isRunning {
            try writeLine(fileDescriptor, hello)
            let deadline = Date().addingTimeInterval(Double(Self.challengeAttemptMilliseconds) / 1_000)
            while boardNonce == nil && isRunning && Date() < deadline {
                let remaining = max(1, Int32(deadline.timeIntervalSinceNow * 1_000))
                guard let challenge = try nextProtocolLine(
                    fileDescriptor,
                    timeoutMilliseconds: remaining
                ) else { break }
                let parts = challenge.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count == 5, parts[0] == USBSessionCryptography.prefix,
                      parts[1] == "CHALLENGE", parts[2] == boardID,
                      let candidateNonce = USBSessionCryptography.data(hex: parts[3]), candidateNonce.count == 32,
                      let receivedCode = USBSessionCryptography.data(hex: parts[4]), receivedCode.count == 32
                else { continue }
                if HMAC<SHA256>.isValidAuthenticationCode(
                    receivedCode,
                    authenticating: authenticationPayload(
                        label: "challenge",
                        clientNonce: clientNonce,
                        boardNonce: candidateNonce
                    ),
                    using: SymmetricKey(data: secret)
                ) {
                    boardNonce = candidateNonce
                } else {
                    sawAuthenticatedMismatch = true
                }
            }
        }
        guard let boardNonce else {
            throw sawAuthenticatedMismatch
                ? USBSerialChannelError.challengeAuthenticationFailed
                : USBSerialChannelError.handshakeTimedOut
        }
        let responseCode = USBSessionCryptography.authenticationCode(
            label: "auth",
            secret: secret,
            clientNonce: clientNonce,
            boardNonce: boardNonce,
            boardID: boardID
        )
        let auth = "\(USBSessionCryptography.prefix) AUTH \(USBSessionCryptography.hex(responseCode))"
        try writeLine(fileDescriptor, auth)
        let authDeadline = Date().addingTimeInterval(5)
        var ready = false
        repeat {
            if let line = try nextProtocolLine(fileDescriptor, timeoutMilliseconds: 1_000),
               line == "\(USBSessionCryptography.prefix) READY" {
                ready = true
            }
        } while !ready && isRunning && Date() < authDeadline
        guard ready else { throw USBSerialChannelError.authenticationResponseRejected }
        key = USBSessionCryptography.sessionKey(
            secret: secret,
            clientNonce: clientNonce,
            boardNonce: boardNonce
        )
    }

    private func authenticationPayload(label: String, clientNonce: Data, boardNonce: Data) -> Data {
        var payload = Data("ILOUSB1 \(label)".utf8)
        payload.append(clientNonce)
        payload.append(boardNonce)
        payload.append(Data(boardID.utf8))
        return payload
    }

    private func sendPendingFrames(_ fileDescriptor: Int32) throws {
        let frames = stateLock.withLock { () -> [Data] in
            let pending = outgoingFrames
            outgoingFrames.removeAll(keepingCapacity: true)
            return pending
        }
        guard let key else { return }
        for frame in frames {
            sendSequence += 1
            let encrypted = try USBSessionCryptography.seal(
                frame,
                key: key,
                direction: "M",
                sequence: sendSequence
            )
            try writeLine(
                fileDescriptor,
                "\(USBSessionCryptography.prefix) DATA M \(sendSequence) \(encrypted.base64EncodedString())"
            )
        }
    }

    private func handleEncryptedLine(_ line: String) throws {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 5, parts[0] == USBSessionCryptography.prefix,
              parts[1] == "DATA", parts[2] == "B",
              let sequence = UInt64(parts[3]), sequence == receiveSequence + 1,
              let encrypted = Data(base64Encoded: parts[4]),
              let key
        else { throw USBSerialChannelError.invalidEncryptedFrame }
        let plaintext = try USBSessionCryptography.open(
            encrypted,
            key: key,
            direction: "B",
            sequence: sequence
        )
        guard plaintext.count <= boardProtocolMaximumFrameBytes + 4 else {
            throw USBSerialChannelError.inputTooLarge
        }
        receiveSequence = sequence
        emit(.data(plaintext))
    }

    private func nextProtocolLine(_ fileDescriptor: Int32, timeoutMilliseconds: Int32) throws -> String? {
        let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1_000)
        while Date() < deadline {
            let remaining = max(1, Int32(deadline.timeIntervalSinceNow * 1_000))
            if let line = try readLine(fileDescriptor, timeoutMilliseconds: remaining),
               line.hasPrefix(USBSessionCryptography.prefix) {
                return line
            }
        }
        return nil
    }

    private func readLine(_ fileDescriptor: Int32, timeoutMilliseconds: Int32) throws -> String? {
        if let line = extractLine() { return line }
        var pollDescriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
        let result = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
        guard result >= 0 else {
            if errno == EINTR { return nil }
            throw USBSerialChannelError.disconnected
        }
        guard result > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4_096)
        let count = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return Darwin.read(fileDescriptor, baseAddress, buffer.count)
        }
        guard count > 0 else { throw USBSerialChannelError.disconnected }
        incomingBuffer.append(contentsOf: bytes.prefix(count))
        guard incomingBuffer.count <= Self.maximumLineBytes else { throw USBSerialChannelError.inputTooLarge }
        return extractLine()
    }

    private func extractLine() -> String? {
        guard let newline = incomingBuffer.firstIndex(of: 0x0A) else { return nil }
        var line = incomingBuffer.prefix(upTo: newline)
        incomingBuffer.removeSubrange(...newline)
        if line.last == 0x0D { line = line.dropLast() }
        return String(data: line, encoding: .utf8)
    }

    private func writeLine(_ fileDescriptor: Int32, _ line: String) throws {
        var data = Data(line.utf8)
        data.append(0x0A)
        guard data.count <= Self.maximumLineBytes else { throw USBSerialChannelError.inputTooLarge }
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let count = Darwin.write(fileDescriptor, base.advanced(by: sent), rawBuffer.count - sent)
                guard count > 0 else {
                    if errno == EINTR { continue }
                    throw USBSerialChannelError.disconnected
                }
                sent += count
            }
        }
    }

    private func emit(_ event: BoardConnectionChannelEvent) {
        let destination = stateLock.withLock { (eventQueue, eventHandler) }
        destination.0?.async { destination.1?(event) }
    }

    private func finish(_ message: String?) {
        let shouldEmit = stateLock.withLock { () -> Bool in
            guard !didClose else { return false }
            didClose = true
            running = false
            if descriptor >= 0 {
                Darwin.close(descriptor)
                descriptor = -1
            }
            outgoingFrames.removeAll()
            key = nil
            return true
        }
        if shouldEmit { emit(.closed(message)) }
    }
}
