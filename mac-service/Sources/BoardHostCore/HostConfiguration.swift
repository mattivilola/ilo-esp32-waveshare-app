import Foundation

public enum HostConfigurationError: Error, LocalizedError, Sendable {
    case notProvisioned
    case invalid

    public var errorDescription: String? {
        switch self {
        case .notProvisioned:
            "No board is provisioned. Run ./tools/board provision first."
        case .invalid:
            "The board host configuration is invalid. Provision the board again."
        }
    }
}

public struct HostConfiguration: Codable, Equatable, Sendable {
    public let boardID: String
    public let port: UInt16
    public let protocolVersion: Int

    public init(boardID: String, port: UInt16, protocolVersion: Int = 1) {
        self.boardID = boardID
        self.port = port
        self.protocolVersion = protocolVersion
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ILO Board Host/board.json")
    }

    public static func load(from url: URL = defaultURL) throws -> HostConfiguration {
        guard let data = try? Data(contentsOf: url) else {
            throw HostConfigurationError.notProvisioned
        }
        guard let configuration = try? JSONDecoder().decode(HostConfiguration.self, from: data),
              KeychainPSKStore.valid(boardID: configuration.boardID),
              configuration.port > 0,
              configuration.protocolVersion == 1
        else {
            throw HostConfigurationError.invalid
        }
        return configuration
    }
}
