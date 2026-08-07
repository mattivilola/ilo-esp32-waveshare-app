import Foundation
import Security

public enum PairingError: Error, LocalizedError, Sendable {
    case invalidBoardID
    case invalidSecret
    case notFound
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidBoardID: "Board ID must contain 1–80 letters, digits, dots, dashes, or underscores."
        case .invalidSecret: "Pairing secret must contain exactly 32 bytes."
        case .notFound: "No pairing exists for this board ID."
        case let .keychain(status): "Keychain operation failed with status \(status)."
        }
    }
}

public struct KeychainPSKStore: Sendable {
    private let service = "com.iloapps.iloboard.host.psk"

    public init() {}

    public func create(boardID: String) throws -> Data {
        guard Self.valid(boardID: boardID) else { throw PairingError.invalidBoardID }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw PairingError.invalidSecret
        }
        let secret = Data(bytes)
        try save(secret: secret, boardID: boardID)
        return secret
    }

    public func save(secret: Data, boardID: String) throws {
        guard Self.valid(boardID: boardID) else { throw PairingError.invalidBoardID }
        guard secret.count == 32 else { throw PairingError.invalidSecret }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: boardID,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = secret
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw PairingError.keychain(status) }
    }

    public func load(boardID: String) throws -> Data {
        guard Self.valid(boardID: boardID) else { throw PairingError.invalidBoardID }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: boardID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw PairingError.notFound }
        guard status == errSecSuccess, let secret = result as? Data else {
            throw PairingError.keychain(status)
        }
        guard secret.count == 32 else { throw PairingError.invalidSecret }
        return secret
    }

    private static func valid(boardID: String) -> Bool {
        guard (1...80).contains(boardID.count) else { return false }
        return boardID.allSatisfy { $0.isLetter || $0.isNumber || ".-_".contains($0) }
    }
}

