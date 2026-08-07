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
            let boardID = value(after: "--board-id", in: arguments) ?? "waveshare-94a990ca5b7c"
            let secret = try KeychainPSKStore().create(boardID: boardID)
            print("Pairing created in the macOS Keychain.")
            print("Board ID: \(boardID)")
            print("PSK (shown once for USB provisioning): \(secret.map { String(format: "%02x", $0) }.joined())")
        case "snapshot":
            let snapshot = try await MockTaskSource().snapshot(revision: 1)
            let data = try ProtocolJSON.encoder().encode(snapshot)
            print(String(decoding: data, as: UTF8.self))
        case "serve":
            let boardID = value(after: "--board-id", in: arguments) ?? "waveshare-94a990ca5b7c"
            let port = UInt16(value(after: "--port", in: arguments) ?? "0") ?? 0
            let secret = try KeychainPSKStore().load(boardID: boardID)
            let server = BoardServer(boardID: boardID, secret: secret, source: MockTaskSource())
            try server.start(port: port)
            print("Serving sanitized mock task status for board \(boardID).")
            print("Remote actions are disabled.")
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        case "doctor":
            print("ILO Board Host")
            print("  protocol: v\(boardProtocolVersion), tasks.read only")
            print("  service: _iloboard._tcp")
            print("  transport: TLS 1.2 PSK")
            print("  Codex adapter: disabled (mock source)")
        default:
            printUsage()
        }
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func printUsage() {
        print("""
        Usage:
          ilo-board-host doctor
          ilo-board-host snapshot
          ilo-board-host pair [--board-id ID]
          ilo-board-host serve --mock [--board-id ID] [--port PORT]
        """)
    }
}

