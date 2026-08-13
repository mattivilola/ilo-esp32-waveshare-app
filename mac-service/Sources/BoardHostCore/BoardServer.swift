import BoardProtocol
import Darwin
import Foundation
import Network
import OSLog
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
    case boardConnected(transport: BoardTransport)
    case boardVersionReceived(String)
    case firmwareUpdateStatus(FirmwareUpdateStatusMessage)
    case focusCompleted(FocusCompletionMessage)
    case boardDisconnected(transport: BoardTransport)
    case transportIssue(transport: BoardTransport, message: String)
    case snapshotSent(at: Date)
}

public enum BoardTransport: String, Equatable, Sendable {
    case wifi
    case usb
}

public final class BoardServer: @unchecked Sendable {
    private let boardID: String
    private let secret: Data
    private let source: any TaskSource
    private let powerStatusSource: any MacPowerStatusProviding
    private let xNewsRefreshCoordinator: XNewsRefreshCoordinator
    private let weatherLocationSource: any WeatherLocationProviding
    private let companionVersion: String?
    private let eventHandler: @Sendable (BoardServerEvent) -> Void
    private let screenCaptureHandler: (@Sendable (Result<CapturedScreen, ScreenCaptureError>) -> Void)?
    private let queue = DispatchQueue(label: "com.iloapps.iloboard.host.network")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: (connection: BoardConnection, transport: BoardTransport)] = [:]
    private var activeConnectionID: ObjectIdentifier?
    private var nextUSBRetry = Date.distantPast
    private var usbFallbackPath: String?
    private var listenerPort: UInt16?

    public init(
        boardID: String,
        secret: Data,
        source: any TaskSource,
        powerStatusSource: any MacPowerStatusProviding = CachedMacPowerStatusSource(),
        xNewsRefreshCoordinator: XNewsRefreshCoordinator = .shared,
        weatherLocationSource: any WeatherLocationProviding = NoWeatherLocationSource(),
        companionVersion: String? = nil,
        eventHandler: @escaping @Sendable (BoardServerEvent) -> Void = { _ in }
    ) {
        self.boardID = boardID
        self.secret = secret
        self.source = source
        self.powerStatusSource = powerStatusSource
        self.xNewsRefreshCoordinator = xNewsRefreshCoordinator
        self.weatherLocationSource = weatherLocationSource
        self.companionVersion = companionVersion
        self.screenCaptureHandler = nil
        self.eventHandler = eventHandler
    }

    public init(
        boardID: String,
        secret: Data,
        source: any TaskSource,
        powerStatusSource: any MacPowerStatusProviding = CachedMacPowerStatusSource(),
        xNewsRefreshCoordinator: XNewsRefreshCoordinator = .shared,
        weatherLocationSource: any WeatherLocationProviding = NoWeatherLocationSource(),
        companionVersion: String? = nil,
        screenCaptureHandler: @escaping @Sendable (Result<CapturedScreen, ScreenCaptureError>) -> Void,
        eventHandler: @escaping @Sendable (BoardServerEvent) -> Void = { _ in }
    ) {
        self.boardID = boardID
        self.secret = secret
        self.source = source
        self.powerStatusSource = powerStatusSource
        self.xNewsRefreshCoordinator = xNewsRefreshCoordinator
        self.weatherLocationSource = weatherLocationSource
        self.companionVersion = companionVersion
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
                    self.listenerPort = port
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
            self.connections.values.forEach { $0.connection.cancel() }
            self.connections.removeAll()
            self.activeConnectionID = nil
        }
    }

    public func updateUSBFallback(path fallbackPath: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.usbFallbackPath = fallbackPath
            self.startUSBFallbackIfNeeded()
        }
    }

    private func startUSBFallbackIfNeeded() {
        let fallbackPath = usbFallbackPath
        let usbEntries = connections.filter { $0.value.transport == .usb }
        guard let fallbackPath else {
            usbEntries.values.forEach { $0.connection.cancel() }
            return
        }
        if activeTransport == .wifi || !usbEntries.isEmpty || Date() < nextUSBRetry { return }
        accept(
            USBSerialBoardConnectionChannel(
                path: fallbackPath,
                boardID: boardID,
                secret: secret
            ),
            transport: .usb
        )
    }

    public func requestFirmwareUpdate(_ action: FirmwareUpdateAction) {
        queue.async { [weak self] in
            guard let self, let activeConnectionID = self.activeConnectionID else { return }
            self.connections[activeConnectionID]?.connection.sendFirmwareUpdateCommand(action)
        }
    }

    private func accept(_ connection: NWConnection) {
        let connectionLimit = screenCaptureHandler == nil ? 4 : 1
        let wifiConnectionCount = connections.values.filter { $0.transport == .wifi }.count
        guard wifiConnectionCount < connectionLimit else {
            connection.cancel()
            return
        }
        accept(NetworkBoardConnectionChannel(connection: connection), transport: .wifi)
    }

    private var activeTransport: BoardTransport? {
        guard let activeConnectionID else { return nil }
        return connections[activeConnectionID]?.transport
    }

    private func accept(_ channel: any BoardConnectionChannel, transport: BoardTransport) {
        let captureRequest = screenCaptureHandler.map { _ in ScreenCaptureRequest() }
        let client = BoardConnection(
            channel: channel,
            expectedBoardID: boardID,
            source: source,
            powerStatusSource: powerStatusSource,
            xNewsRefreshCoordinator: xNewsRefreshCoordinator,
            weatherLocationSource: weatherLocationSource,
            companionVersion: companionVersion,
            hostAddress: transport == .usb ? LocalIPv4Address.current() : nil,
            hostPort: transport == .usb ? listenerPort : nil,
            captureRequest: captureRequest,
            onScreenCapture: screenCaptureHandler,
            onReady: { [weak self] id in self?.connectionReady(id: id, transport: transport) },
            onBoardVersion: { [eventHandler] version in eventHandler(.boardVersionReceived(version)) },
            onFirmwareUpdateStatus: { [eventHandler] status in eventHandler(.firmwareUpdateStatus(status)) },
            onFocusCompletion: { [eventHandler] completion in eventHandler(.focusCompleted(completion)) },
            onSnapshot: { [eventHandler] date in eventHandler(.snapshotSent(at: date)) },
            onTransportIssue: { [eventHandler] transport, message in
                eventHandler(.transportIssue(transport: transport, message: message))
            },
            onClose: { [weak self] id in self?.connectionClosed(id: id, transport: transport) }
        )
        connections[ObjectIdentifier(client)] = (client, transport)
        client.start(queue: queue)
    }

    private func connectionReady(id: ObjectIdentifier, transport: BoardTransport) {
        guard connections[id] != nil else { return }
        if transport == .usb, activeTransport == .wifi {
            connections[id]?.connection.cancel()
            return
        }
        activeConnectionID = id
        if transport == .usb { nextUSBRetry = .distantPast }
        if transport == .wifi {
            connections
                .filter { $0.key != id && $0.value.transport == .usb }
                .values
                .forEach { $0.connection.cancel() }
        }
        eventHandler(.boardConnected(transport: transport))
    }

    private func connectionClosed(id: ObjectIdentifier, transport: BoardTransport) {
        connections.removeValue(forKey: id)
        if transport == .usb {
            nextUSBRetry = Date().addingTimeInterval(6)
            queue.asyncAfter(deadline: .now() + 6) { [weak self] in
                self?.startUSBFallbackIfNeeded()
            }
        }
        guard activeConnectionID == id else { return }
        activeConnectionID = nil
        eventHandler(.boardDisconnected(transport: transport))
    }
}

private final class BoardConnection: @unchecked Sendable {
    private let statusLog = Logger(subsystem: "com.iloapps.iloboard", category: "BoardSnapshot")
    private let channel: any BoardConnectionChannel
    private let expectedBoardID: String
    private let source: any TaskSource
    private let powerStatusSource: any MacPowerStatusProviding
    private let xNewsRefreshCoordinator: XNewsRefreshCoordinator
    private let weatherLocationSource: any WeatherLocationProviding
    private let companionVersion: String?
    private let hostAddress: String?
    private let hostPort: UInt16?
    private let captureRequest: ScreenCaptureRequest?
    private let onScreenCapture: (@Sendable (Result<CapturedScreen, ScreenCaptureError>) -> Void)?
    private let onReady: @Sendable (ObjectIdentifier) -> Void
    private let onBoardVersion: @Sendable (String) -> Void
    private let onFirmwareUpdateStatus: @Sendable (FirmwareUpdateStatusMessage) -> Void
    private let onFocusCompletion: @Sendable (FocusCompletionMessage) -> Void
    private let onSnapshot: @Sendable (Date) -> Void
    private let onTransportIssue: @Sendable (BoardTransport, String) -> Void
    private let onClose: @Sendable (ObjectIdentifier) -> Void
    private let transport: BoardTransport
    private var decoder = FrameDecoder()
    private var helloAccepted = false
    private var subscribed = false
    private var revision: UInt64 = 0
    private var captureAssembler: ScreenCaptureAssembler?
    private var captureFinished = false
    private var lastWeatherLocationPresence: Bool?

    init(
        channel: any BoardConnectionChannel,
        expectedBoardID: String,
        source: any TaskSource,
        powerStatusSource: any MacPowerStatusProviding,
        xNewsRefreshCoordinator: XNewsRefreshCoordinator,
        weatherLocationSource: any WeatherLocationProviding,
        companionVersion: String?,
        hostAddress: String?,
        hostPort: UInt16?,
        captureRequest: ScreenCaptureRequest?,
        onScreenCapture: (@Sendable (Result<CapturedScreen, ScreenCaptureError>) -> Void)?,
        onReady: @escaping @Sendable (ObjectIdentifier) -> Void,
        onBoardVersion: @escaping @Sendable (String) -> Void,
        onFirmwareUpdateStatus: @escaping @Sendable (FirmwareUpdateStatusMessage) -> Void,
        onFocusCompletion: @escaping @Sendable (FocusCompletionMessage) -> Void,
        onSnapshot: @escaping @Sendable (Date) -> Void,
        onTransportIssue: @escaping @Sendable (BoardTransport, String) -> Void,
        onClose: @escaping @Sendable (ObjectIdentifier) -> Void
    ) {
        self.channel = channel
        self.expectedBoardID = expectedBoardID
        self.source = source
        self.powerStatusSource = powerStatusSource
        self.xNewsRefreshCoordinator = xNewsRefreshCoordinator
        self.weatherLocationSource = weatherLocationSource
        self.companionVersion = companionVersion
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.captureRequest = captureRequest
        self.onScreenCapture = onScreenCapture
        self.captureAssembler = captureRequest.map { ScreenCaptureAssembler(requestID: $0.requestID) }
        self.onReady = onReady
        self.onBoardVersion = onBoardVersion
        self.onFirmwareUpdateStatus = onFirmwareUpdateStatus
        self.onFocusCompletion = onFocusCompletion
        self.onSnapshot = onSnapshot
        self.onTransportIssue = onTransportIssue
        self.onClose = onClose
        self.transport = channel is USBSerialBoardConnectionChannel ? .usb : .wifi
    }

    func start(queue: DispatchQueue) {
        channel.start(queue: queue) { [weak self] event in
            guard let self else { return }
            switch event {
            case .ready:
                self.captureLog("Authenticated connection ready")
                self.onReady(ObjectIdentifier(self))
            case let .data(data):
                self.receive(data)
            case let .closed(message):
                self.captureLog("Connection closed")
                if let message { self.captureLog(message) }
                if let message { self.onTransportIssue(self.transport, message) }
                self.onClose(ObjectIdentifier(self))
            }
        }
    }

    func cancel() {
        subscribed = false
        channel.cancel()
    }

    private func receive(_ data: Data) {
        do {
            for payload in try decoder.append(data) {
                handle(payload)
            }
        } catch {
            send(ErrorMessage(code: "invalidFrame", message: "Frame is empty or too large."))
            channel.cancel()
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
                channel.cancel()
                return
            }
            helloAccepted = true
            if let firmwareVersion = message.firmwareVersion,
               Self.validSoftwareVersion(firmwareVersion) {
                onBoardVersion(firmwareVersion)
            }
            captureLog("Board hello accepted")
            send(HelloAcknowledgement(
                hostAddress: hostAddress,
                hostPort: hostPort
            ))
        case "subscribe":
            guard helloAccepted else {
                send(ErrorMessage(code: "helloRequired", message: "Send hello before subscribing."))
                return
            }
            captureLog("Board subscribed; requesting framebuffer")
            beginSubscription()
        case "screenCaptureBegin":
            captureLog("Framebuffer transfer started")
            handleCaptureMessage(payload, as: ScreenCaptureBeginMessage.self) { assembler, message in
                try assembler.begin(message)
                return nil
            }
        case "screenCaptureChunk":
            handleCaptureMessage(payload, as: ScreenCaptureChunkMessage.self) { assembler, message in
                try assembler.append(message)
                let received = message.sequence + 1
                if received == 1 || received.isMultiple(of: 100) {
                    captureLog("Received capture chunk \(received)/\(screenCaptureChunkCount)")
                }
                return nil
            }
        case "screenCaptureResult":
            captureLog("Framebuffer transfer result received")
            handleCaptureMessage(payload, as: ScreenCaptureResultMessage.self) { assembler, message in
                try assembler.finish(message)
            }
        case "xNewsRefreshRequest":
            handleXNewsRefreshRequest(payload)
        case "codexChatRequest":
            handleCodexChatRequest(payload)
        case "codexContinueRequest":
            handleCodexContinueRequest(payload)
        case "focusCompletion":
            guard helloAccepted, subscribed,
                  let completion = try? ProtocolJSON.decoder().decode(FocusCompletionMessage.self, from: payload),
                  Self.validFocusCompletion(completion)
            else {
                send(ErrorMessage(code: "invalidFocusCompletion", message: "Focus completion payload is invalid."))
                return
            }
            send(FocusCompletionAcknowledgement(eventID: completion.eventID))
            onFocusCompletion(completion)
        case "firmwareUpdateStatus":
            guard helloAccepted, subscribed,
                  let status = try? ProtocolJSON.decoder().decode(FirmwareUpdateStatusMessage.self, from: payload),
                  Self.validFirmwareUpdateStatus(status)
            else {
                send(ErrorMessage(code: "invalidFirmwareUpdateStatus", message: "Firmware update status is invalid."))
                return
            }
            onFirmwareUpdateStatus(status)
        default:
            send(ErrorMessage(code: "unsupportedCapability", message: "Protocol v1 does not support this capability."))
        }
    }

    private func captureLog(_ message: String) {
        if captureRequest != nil {
            print("[capture] \(message)")
        }
    }

    func sendFirmwareUpdateCommand(_ action: FirmwareUpdateAction) {
        guard helloAccepted, subscribed else { return }
        send(FirmwareUpdateCommand(action: action))
    }

    private static func validFirmwareUpdateStatus(_ status: FirmwareUpdateStatusMessage) -> Bool {
        status.type == "firmwareUpdateStatus"
            && status.version == 1
            && validSoftwareVersion(status.currentVersion)
            && (status.availableVersion.map(validSoftwareVersion) ?? true)
            && (0...100).contains(status.progressPercent)
            && (1...95).contains(status.message.count)
            && status.message.allSatisfy { $0.isASCII && !$0.isNewline }
    }

    private static func validFocusCompletion(_ completion: FocusCompletionMessage) -> Bool {
        completion.type == "focusCompletion"
            && completion.version == focusCompletionProtocolVersion
            && validRequestID(completion.eventID)
            && (1...720).contains(completion.durationMinutes)
            && (1_704_067_200...4_102_444_799).contains(completion.completedEpoch)
    }

    private func handleXNewsRefreshRequest(_ payload: Data) {
        guard helloAccepted, subscribed,
              let request = try? ProtocolJSON.decoder().decode(XNewsRefreshRequest.self, from: payload),
              request.type == "xNewsRefreshRequest",
              Self.validRequestID(request.requestID)
        else {
            send(ErrorMessage(code: "invalidXNewsRefresh", message: "A subscribed session and bounded request ID are required."))
            return
        }
        send(XNewsRefreshStatusMessage(
            requestID: request.requestID,
            status: .fetching,
            message: "Fetching latest AI news"
        ))
        Task { [weak self, xNewsRefreshCoordinator] in
            let outcome = await xNewsRefreshCoordinator.requestManualRefresh()
            guard let self else { return }
            let response: (XNewsRefreshStatus, String) = switch outcome {
            case .updated: (.updated, "Latest verified stories are ready")
            case .disabled: (.disabled, "Enable X News on the Mac first")
            case .cooldown: (.cooldown, "Refresh available after the 15 minute cooldown")
            case .busy: (.busy, "A news refresh is already running")
            case .failed: (.failed, "No verified update was accepted")
            }
            self.send(XNewsRefreshStatusMessage(
                requestID: request.requestID,
                status: response.0,
                message: response.1
            ))
        }
    }

    private func handleCodexContinueRequest(_ payload: Data) {
        guard helloAccepted, subscribed,
              let request = try? ProtocolJSON.decoder().decode(CodexContinueRequest.self, from: payload),
              request.type == "codexContinueRequest",
              request.version == 1,
              request.action == "continue",
              Self.validRequestID(request.requestID),
              Self.validTaskID(request.taskID)
        else {
            send(ErrorMessage(
                code: "invalidCodexContinue",
                message: "A subscribed session, fixed action, and bounded identifiers are required."
            ))
            return
        }
        Task { [weak self, source] in
            let outcome = await source.continueTask(id: request.taskID, requestID: request.requestID)
            guard let self else { return }
            let response: (CodexContinueStatus, String) = switch outcome {
            case .accepted: (.accepted, "Please continue was sent")
            case .unavailable: (.unavailable, "Task control is unavailable")
            case .busy: (.busy, "Codex is busy; try again")
            case .rejected: (.rejected, "Task is not eligible to continue")
            case .failed: (.failed, "Codex did not accept the request")
            }
            self.send(CodexContinueStatusMessage(
                requestID: request.requestID,
                status: response.0,
                message: response.1
            ))
        }
    }

    private func handleCodexChatRequest(_ payload: Data) {
        guard helloAccepted, subscribed,
              let request = try? ProtocolJSON.decoder().decode(CodexChatRequest.self, from: payload),
              request.type == "codexChatRequest",
              request.version == codexChatProtocolVersion,
              Self.validRequestID(request.requestID),
              Self.validTaskID(request.taskID)
        else {
            send(ErrorMessage(
                code: "invalidCodexChatRequest",
                message: "A subscribed session and bounded identifiers are required."
            ))
            return
        }
        Task { [weak self, source] in
            let outcome = await source.chatDetail(id: request.taskID)
            guard let self else { return }
            let response: CodexChatDetailMessage = switch outcome {
            case let .ready(title, messages):
                CodexChatDetailMessage(
                    requestID: request.requestID,
                    taskID: request.taskID,
                    status: .ready,
                    title: BoardDisplayText.sanitized(title, maximum: 80),
                    messages: CodexChatSanitizer.sanitize(messages),
                    message: messages.isEmpty ? "No recent text messages" : nil
                )
            case .unavailable:
                CodexChatDetailMessage(
                    requestID: request.requestID,
                    taskID: request.taskID,
                    status: .unavailable,
                    title: "",
                    message: "Recent chat is unavailable"
                )
            case .busy:
                CodexChatDetailMessage(
                    requestID: request.requestID,
                    taskID: request.taskID,
                    status: .busy,
                    title: "",
                    message: "Codex is busy; try again"
                )
            case .failed:
                CodexChatDetailMessage(
                    requestID: request.requestID,
                    taskID: request.taskID,
                    status: .failed,
                    title: "",
                    message: "Recent chat could not be loaded"
                )
            }
            self.send(response)
        }
    }

    private static func validRequestID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
        }
    }

    private static func validTaskID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
        }
    }

    private static func validSoftwareVersion(_ value: String) -> Bool {
        (1...32).contains(value.count) && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || ".()+-".contains($0))
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
            channel.cancel()
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
            channel.cancel()
        } catch {
            finishCapture(.failure(.invalidMetadata))
            channel.cancel()
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
            let weatherLocation = await weatherLocationSource.currentLocation()
            let hasWeatherLocation = weatherLocation != nil
            if lastWeatherLocationPresence != hasWeatherLocation {
                lastWeatherLocationPresence = hasWeatherLocation
                statusLog.notice("Outgoing board snapshot weather location present: \(hasWeatherLocation, privacy: .public)")
            }
            let tasks = raw.tasks.map(TaskSanitizer.sanitize)
            let snapshot = DashboardSnapshot(
                revision: raw.revision,
                generatedAt: raw.generatedAt,
                hostState: raw.hostState,
                tasks: tasks,
                codexEnabled: raw.codexEnabled,
                codexContinueEnabled: raw.capabilities.contains("tasks.continue.fixed"),
                xNewsEnabled: raw.xNewsEnabled,
                newsFeed: raw.newsFeed,
                macPower: macPower,
                hostTime: HostTimeStatus(),
                weatherLocation: weatherLocation,
                companionVersion: companionVersion
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
            channel.send(frame)
        } catch {
            channel.cancel()
        }
    }
}
