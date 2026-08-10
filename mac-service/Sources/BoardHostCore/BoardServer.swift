import BoardProtocol
import Foundation
import Network
import Security

public enum BoardServerError: Error, LocalizedError, Sendable {
    case cannotCreateListener(String)

    public var errorDescription: String? {
        switch self {
        case let .cannotCreateListener(message): "Cannot create board listener: \(message)"
        }
    }
}

public enum BoardServerEvent: Equatable, Sendable {
    case listenerReady(port: UInt16)
    case listenerFailed(message: String)
    case boardConnected
    case boardDisconnected
    case snapshotSent(at: Date)
}

public final class BoardServer: @unchecked Sendable {
    private let boardID: String
    private let secret: Data
    private let source: any TaskSource
    private let powerStatusSource: any MacPowerStatusProviding
    private let eventHandler: @Sendable (BoardServerEvent) -> Void
    private let screenCaptureHandler: (@Sendable (Result<CapturedScreen, ScreenCaptureError>) -> Void)?
    private let queue = DispatchQueue(label: "com.iloapps.iloboard.host.network")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: BoardConnection] = [:]

    public init(
        boardID: String,
        secret: Data,
        source: any TaskSource,
        powerStatusSource: any MacPowerStatusProviding = CachedMacPowerStatusSource(),
        eventHandler: @escaping @Sendable (BoardServerEvent) -> Void = { _ in }
    ) {
        self.boardID = boardID
        self.secret = secret
        self.source = source
        self.powerStatusSource = powerStatusSource
        self.screenCaptureHandler = nil
        self.eventHandler = eventHandler
    }

    public init(
        boardID: String,
        secret: Data,
        source: any TaskSource,
        powerStatusSource: any MacPowerStatusProviding = CachedMacPowerStatusSource(),
        screenCaptureHandler: @escaping @Sendable (Result<CapturedScreen, ScreenCaptureError>) -> Void,
        eventHandler: @escaping @Sendable (BoardServerEvent) -> Void = { _ in }
    ) {
        self.boardID = boardID
        self.secret = secret
        self.source = source
        self.powerStatusSource = powerStatusSource
        self.screenCaptureHandler = screenCaptureHandler
        self.eventHandler = eventHandler
    }

    public func start(port: UInt16 = 0) throws {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        let cipher = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        sec_protocol_options_append_tls_ciphersuite(options, cipher)
        secret.withUnsafeBytes { (secretBytes: UnsafeRawBufferPointer) in
            boardID.data(using: .utf8)!.withUnsafeBytes { (identityBytes: UnsafeRawBufferPointer) in
                let psk = DispatchData(bytes: secretBytes)
                let identity = DispatchData(bytes: identityBytes)
                sec_protocol_options_add_pre_shared_key(
                    options,
                    psk as dispatch_data_t,
                    identity as dispatch_data_t
                )
            }
        }

        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.allowLocalEndpointReuse = true
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? .any
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: endpointPort)
        } catch {
            throw BoardServerError.cannotCreateListener(error.localizedDescription)
        }
        let txt = NetService.data(fromTXTRecord: [
            "v": Data("1".utf8),
            "transport": Data("tls-psk-tcp".utf8),
        ])
        listener.service = NWListener.Service(
            name: "ilo-board-host-\(String(boardID.suffix(8)))",
            type: "_iloboard._tcp",
            domain: nil,
            txtRecord: txt
        )
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                print("ILO Board host ready on \(listener?.port?.debugDescription ?? "dynamic port")")
                print("Bonjour: _iloboard._tcp (TLS-PSK, protocol v1)")
                if let port = listener?.port?.rawValue {
                    self.eventHandler(.listenerReady(port: port))
                }
            case let .failed(error):
                fputs("Listener failed: \(error)\n", stderr)
                self.eventHandler(.listenerFailed(message: error.localizedDescription))
            case .cancelled:
                print("ILO Board host stopped")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        let connectionLimit = screenCaptureHandler == nil ? 4 : 1
        guard connections.count < connectionLimit else {
            connection.cancel()
            return
        }
        let captureRequest = screenCaptureHandler.map { _ in ScreenCaptureRequest() }
        let client = BoardConnection(
            connection: connection,
            expectedBoardID: boardID,
            source: source,
            powerStatusSource: powerStatusSource,
            captureRequest: captureRequest,
            onScreenCapture: screenCaptureHandler,
            onReady: { [eventHandler] in eventHandler(.boardConnected) },
            onSnapshot: { [eventHandler] date in eventHandler(.snapshotSent(at: date)) },
            onClose: { [weak self, eventHandler] id in
                self?.connections.removeValue(forKey: id)
                eventHandler(.boardDisconnected)
            }
        )
        connections[ObjectIdentifier(client)] = client
        client.start(queue: queue)
    }
}

private final class BoardConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let expectedBoardID: String
    private let source: any TaskSource
    private let powerStatusSource: any MacPowerStatusProviding
    private let captureRequest: ScreenCaptureRequest?
    private let onScreenCapture: (@Sendable (Result<CapturedScreen, ScreenCaptureError>) -> Void)?
    private let onReady: @Sendable () -> Void
    private let onSnapshot: @Sendable (Date) -> Void
    private let onClose: @Sendable (ObjectIdentifier) -> Void
    private var decoder = FrameDecoder()
    private var helloAccepted = false
    private var subscribed = false
    private var revision: UInt64 = 0
    private var captureAssembler: ScreenCaptureAssembler?
    private var captureFinished = false

    init(
        connection: NWConnection,
        expectedBoardID: String,
        source: any TaskSource,
        powerStatusSource: any MacPowerStatusProviding,
        captureRequest: ScreenCaptureRequest?,
        onScreenCapture: (@Sendable (Result<CapturedScreen, ScreenCaptureError>) -> Void)?,
        onReady: @escaping @Sendable () -> Void,
        onSnapshot: @escaping @Sendable (Date) -> Void,
        onClose: @escaping @Sendable (ObjectIdentifier) -> Void
    ) {
        self.connection = connection
        self.expectedBoardID = expectedBoardID
        self.source = source
        self.powerStatusSource = powerStatusSource
        self.captureRequest = captureRequest
        self.onScreenCapture = onScreenCapture
        self.captureAssembler = captureRequest.map { ScreenCaptureAssembler(requestID: $0.requestID) }
        self.onReady = onReady
        self.onSnapshot = onSnapshot
        self.onClose = onClose
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onReady()
                self.receive()
            case .failed, .cancelled:
                self.finishCapture(.failure(.connectionClosed))
                self.onClose(ObjectIdentifier(self))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        subscribed = false
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: boardProtocolMaximumFrameBytes + 4) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for payload in try self.decoder.append(data) {
                        self.handle(payload)
                    }
                } catch {
                    self.send(ErrorMessage(code: "invalidFrame", message: "Frame is empty or too large."))
                    self.connection.cancel()
                    return
                }
            }
            if complete || error != nil {
                self.connection.cancel()
            } else {
                self.receive()
            }
        }
    }

    private func handle(_ payload: Data) {
        guard let envelope = try? ProtocolJSON.decoder().decode(MessageEnvelope.self, from: payload) else {
            send(ErrorMessage(code: "invalidMessage", message: "Message is not valid protocol JSON."))
            return
        }
        switch envelope.type {
        case "hello":
            guard let message = try? ProtocolJSON.decoder().decode(ClientMessage.self, from: payload) else {
                send(ErrorMessage(code: "invalidMessage", message: "Hello is not valid protocol JSON."))
                return
            }
            guard message.protocolVersion == boardProtocolVersion else {
                send(ErrorMessage(code: "unsupportedVersion", message: "Protocol version 1 is required."))
                return
            }
            guard message.boardID == expectedBoardID else {
                send(ErrorMessage(code: "boardIdentityMismatch", message: "Board identity does not match the TLS pairing."))
                connection.cancel()
                return
            }
            helloAccepted = true
            send(HelloAcknowledgement())
        case "subscribe":
            guard helloAccepted else {
                send(ErrorMessage(code: "helloRequired", message: "Send hello before subscribing."))
                return
            }
            beginSubscription()
        case "screenCaptureBegin":
            handleCaptureMessage(payload, as: ScreenCaptureBeginMessage.self) { assembler, message in
                try assembler.begin(message)
                return nil
            }
        case "screenCaptureChunk":
            handleCaptureMessage(payload, as: ScreenCaptureChunkMessage.self) { assembler, message in
                try assembler.append(message)
                return nil
            }
        case "screenCaptureResult":
            handleCaptureMessage(payload, as: ScreenCaptureResultMessage.self) { assembler, message in
                try assembler.finish(message)
            }
        default:
            send(ErrorMessage(code: "unsupportedCapability", message: "Protocol v1 supports task status reads only."))
        }
    }

    private func beginSubscription() {
        guard !subscribed else { return }
        subscribed = true
        if let captureRequest {
            send(captureRequest)
            return
        }
        Task { [weak self] in
            while let self, self.subscribed {
                await self.sendSnapshot()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func handleCaptureMessage<Message: Decodable>(
        _ payload: Data,
        as type: Message.Type,
        operation: (inout ScreenCaptureAssembler, Message) throws -> CapturedScreen?
    ) {
        guard helloAccepted, subscribed, var assembler = captureAssembler,
              let message = try? ProtocolJSON.decoder().decode(type, from: payload)
        else {
            send(ErrorMessage(code: "unexpectedCaptureData", message: "No authenticated screen capture is pending."))
            connection.cancel()
            return
        }
        do {
            let capture = try operation(&assembler, message)
            captureAssembler = assembler
            if let capture {
                finishCapture(.success(capture))
            }
        } catch let error as ScreenCaptureError {
            finishCapture(.failure(error))
            connection.cancel()
        } catch {
            finishCapture(.failure(.invalidMetadata))
            connection.cancel()
        }
    }

    private func finishCapture(_ result: Result<CapturedScreen, ScreenCaptureError>) {
        guard !captureFinished, onScreenCapture != nil else { return }
        captureFinished = true
        captureAssembler = nil
        onScreenCapture?(result)
    }

    private func sendSnapshot() async {
        revision += 1
        do {
            let raw = try await source.snapshot(revision: revision)
            let macPower = await powerStatusSource.currentStatus()
            let tasks = raw.tasks.map(TaskSanitizer.sanitize)
            let snapshot = DashboardSnapshot(
                revision: raw.revision,
                generatedAt: raw.generatedAt,
                hostState: raw.hostState,
                tasks: tasks,
                newsFeed: raw.newsFeed,
                macPower: macPower
            )
            send(SnapshotMessage(snapshot: snapshot))
            onSnapshot(Date())
        } catch {
            send(ErrorMessage(code: "sourceUnavailable", message: "Task status is temporarily unavailable."))
        }
    }

    private func send<T: Encodable>(_ message: T) {
        do {
            let payload = try ProtocolJSON.encoder().encode(message)
            let frame = try FrameEncoder.encode(payload)
            connection.send(content: frame, completion: .contentProcessed { error in
                if error != nil { self.connection.cancel() }
            })
        } catch {
            connection.cancel()
        }
    }
}
