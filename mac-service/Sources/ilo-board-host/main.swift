import BoardHostCore
import BoardProtocol
import Foundation

@main
struct ILOBoardHostCommand {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "help"
        switch command {
        case "pair":
            guard arguments.contains("--secret-stdin"),
                  let boardID = value(after: "--board-id", in: arguments),
                  let line = readLine(),
                  let secret = decodeHexSecret(line)
            else {
                throw PairingError.invalidSecret
            }
            try KeychainPSKStore().save(secret: secret, boardID: boardID)
            print("Pairing stored securely in the macOS Keychain for board \(boardID).")
        case "snapshot":
            let mock = arguments.contains("--mock")
            let source: any TaskSource = mock ? MockTaskSource() : CodexHistoryTaskSource()
            let powerSource: any MacPowerStatusProviding = mock
                ? MockMacPowerStatusSource()
                : CachedMacPowerStatusSource()
            let raw = try await source.snapshot(revision: 1)
            let macPower = await powerSource.currentStatus()
            let snapshot = DashboardSnapshot(
                revision: raw.revision,
                generatedAt: raw.generatedAt,
                hostState: raw.hostState,
                tasks: raw.tasks.map(TaskSanitizer.sanitize),
                codexContinueEnabled: raw.capabilities.contains("tasks.continue.fixed"),
                xNewsEnabled: raw.xNewsEnabled,
                newsFeed: raw.newsFeed,
                macPower: macPower,
                hostTime: HostTimeStatus()
            )
            let data = try ProtocolJSON.encoder().encode(snapshot)
            print(String(decoding: data, as: UTF8.self))
        case "serve":
            let configuration = try HostConfiguration.load()
            let boardID = value(after: "--board-id", in: arguments) ?? configuration.boardID
            let port = UInt16(value(after: "--port", in: arguments) ?? "") ?? configuration.port
            let secret = try KeychainPSKStore().load(boardID: boardID)
            let mock = arguments.contains("--mock")
            let source: any TaskSource = mock ? MockTaskSource() : CodexHistoryTaskSource()
            let powerSource: any MacPowerStatusProviding = mock
                ? MockMacPowerStatusSource()
                : CachedMacPowerStatusSource()
            let server = BoardServer(
                boardID: boardID,
                secret: secret,
                source: source,
                powerStatusSource: powerSource
            )
            try server.start(port: port)
            print(arguments.contains("--mock") ? "Serving sanitized mock task status." : "Serving sanitized Codex recent-task history.")
            print("Only hold-confirmed fixed Codex continuation is enabled; other remote actions are disabled.")
            let xNewsScheduleTask = Task { await XNewsRefreshCoordinator.shared.run() }
            defer { xNewsScheduleTask.cancel() }
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        case "screenshot":
            guard let outputPath = value(after: "--output", in: arguments) else {
                throw ScreenCaptureCommandError.outputRequired
            }
            let timeout = try captureTimeout(value(after: "--timeout", in: arguments))
            let outputURL = URL(fileURLWithPath: NSString(string: outputPath).expandingTildeInPath).standardizedFileURL
            let force = arguments.contains("--force")
            if !force && FileManager.default.fileExists(atPath: outputURL.path) {
                throw ScreenCaptureCommandError.outputExists(outputURL.path)
            }
            guard FileManager.default.fileExists(atPath: outputURL.deletingLastPathComponent().path) else {
                throw ScreenCaptureCommandError.outputDirectoryMissing(outputURL.deletingLastPathComponent().path)
            }

            let configuration = try HostConfiguration.load()
            let secret = try KeychainPSKStore().load(boardID: configuration.boardID)
            print("Waiting up to \(timeout) seconds for the paired board. Stop ILOBoardMenu first if it owns the service port.")
            let capture = try await AuthenticatedScreenCapture.capture(
                configuration: configuration,
                secret: secret,
                timeoutSeconds: timeout
            )
            let png = try ScreenCapturePNGEncoder.encode(capture)
            let options: Data.WritingOptions = force ? .atomic : .withoutOverwriting
            try png.write(to: outputURL, options: options)
            print("Saved authenticated 1024x600 board capture: \(outputURL.path)")
        case "doctor":
            print("ILO Board Host")
            print("  protocol: v\(boardProtocolVersion), tasks.read/continue.fixed + macPower.read + xNews.read/refresh.request + display.capture.rgb565")
            print("  service: _iloboard._tcp")
            print("  transport: TLS 1.2 PSK")
            print("  Codex adapter: \(CodexExecutableResolver.resolve()?.path ?? "CLI not found")")
            print("  Desktop task status: recent history only unless owned by this App Server")
            print("  Optional Grok adapter: \(GrokExecutableResolver.resolve()?.path ?? "CLI not found")")
            print("  X News: opt-in; verified cache only; daily policy available")
            if let power = await CachedMacPowerStatusSource().currentStatus() {
                print("  Mac power: \(power.levelPercent)% \(power.state.rawValue)")
            } else {
                print("  Mac power: internal battery unavailable")
            }
        case "x-news":
            try runXNews(arguments: Array(arguments.dropFirst()))
        default:
            printUsage()
        }
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func decodeHexSecret(_ value: String) -> Data? {
        guard value.count == 64 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private static func captureTimeout(_ value: String?) throws -> Int {
        guard let value else { return 45 }
        guard let seconds = Int(value), (1...120).contains(seconds) else {
            throw ScreenCaptureCommandError.invalidTimeout
        }
        return seconds
    }

    private static func runXNews(arguments: [String]) throws {
        switch arguments.first ?? "status" {
        case "status":
            print("Grok CLI: \(GrokExecutableResolver.resolve()?.path ?? "not found")")
            if let feed = try? XNewsFeedCache().load() {
                let timestamp = ISO8601DateFormatter().string(from: feed.generatedAt)
                print("Verified cache: \(feed.stories.count) stories generated \(timestamp)")
            } else {
                print("Verified cache: unavailable")
            }
            let settings = XNewsRefreshSettingsStore().load()
            let feature = XNewsFeatureController().status()
            print("Automatic refresh: \(settings.cadence.rawValue)")
            print("Board screen: \(feature.isEnabled ? "visible" : "hidden")")
            print("Available schedules: daily at 08:00, or 08:00 + 14:00 local")
            print("Manual refresh cooldown: 15 minutes")
        case "refresh":
            guard arguments.contains("--allow-grok-tools") else {
                throw GrokXNewsError.explicitConsentRequired
            }
            let settingsStore = XNewsRefreshSettingsStore()
            let settings = settingsStore.load()
            let now = Date()
            guard XNewsRefreshPolicy(cadence: settings.cadence).allowsManualRefresh(
                lastAttempt: settings.lastAttemptAt,
                now: now
            ) else {
                throw GrokXNewsError.refreshCooldown
            }
            try settingsStore.save(XNewsRefreshSettings(
                cadence: settings.cadence,
                consentVersion: settings.consentVersion,
                lastAttemptAt: now
            ))
            let feed = try GrokXNewsSource().refresh(
                explicitlyAllowsGrokTools: true,
                now: now
            )
            print("Accepted and cached \(feed.stories.count) newly cited X News stories.")
        case "enable":
            guard arguments.contains("--allow-grok-tools") else {
                throw GrokXNewsError.explicitConsentRequired
            }
            let cadence: XNewsRefreshCadence = arguments.contains("--twice-daily") ? .morningAndAfternoon : .daily
            try XNewsFeatureController().enable(cadence: cadence, explicitlyAllowsGrokTools: true)
            print(cadence == .daily
                ? "Enabled X News at 08:00 local each day."
                : "Enabled X News at 08:00 and 14:00 local each day.")
        case "disable":
            try XNewsFeatureController().disable()
            print("Disabled automatic X News refresh. The last verified cache was preserved.")
        default:
            throw XNewsCommandError.invalidAction
        }
    }

    private static func printUsage() {
        print("""
        Usage:
          ilo-board-host doctor
          ilo-board-host snapshot [--mock]
          ilo-board-host pair --board-id ID --secret-stdin
          ilo-board-host serve [--mock] [--board-id ID] [--port PORT]
          ilo-board-host screenshot --output FILE.png [--timeout SECONDS] [--force]
          ilo-board-host x-news status
          ilo-board-host x-news refresh --allow-grok-tools
          ilo-board-host x-news enable [--twice-daily] --allow-grok-tools
          ilo-board-host x-news disable
        """)
    }
}

private enum XNewsCommandError: Error, LocalizedError {
    case invalidAction

    var errorDescription: String? {
        "X News action must be status or refresh."
    }
}

private enum ScreenCaptureCommandError: Error, LocalizedError {
    case outputRequired
    case outputExists(String)
    case outputDirectoryMissing(String)
    case invalidTimeout

    var errorDescription: String? {
        switch self {
        case .outputRequired: "Screenshot output is required. Pass --output FILE.png."
        case let .outputExists(path): "Refusing to overwrite existing file: \(path). Pass --force to replace it."
        case let .outputDirectoryMissing(path): "Screenshot output directory does not exist: \(path)"
        case .invalidTimeout: "Screenshot timeout must be an integer from 1 through 120 seconds."
        }
    }
}
