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
    public let usbSerialNumber: String?

    public init(
        boardID: String,
        port: UInt16,
        protocolVersion: Int = 1,
        usbSerialNumber: String? = nil
    ) {
        self.boardID = boardID
        self.port = port
        self.protocolVersion = protocolVersion
        self.usbSerialNumber = usbSerialNumber.flatMap(Self.normalizedUSBSerialNumber)
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
              configuration.protocolVersion == 1,
              configuration.usbSerialNumber.map({ normalizedUSBSerialNumber($0) != nil }) ?? true
        else {
            throw HostConfigurationError.invalid
        }
        return configuration
    }

    public static func normalizedUSBSerialNumber(_ value: String) -> String? {
        let normalized = value.uppercased().filter(\.isHexDigit)
        guard (12...32).contains(normalized.count) else { return nil }
        return normalized
    }
}
