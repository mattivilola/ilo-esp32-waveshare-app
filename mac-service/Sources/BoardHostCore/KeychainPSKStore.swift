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
    static let legacyService = "com.iloapps.iloboard.host.psk"
    static let companionService = "com.iloapps.iloboard.menu.psk.v1"
    static let companionBundleIdentifier = "com.iloapps.iloboard.menu"
    static let companionTeamIdentifier = "MM233FKU38"

    /// Only the stable ILO Applications signing identity should create or read
    /// the companion-owned copy. `swift run` and ad-hoc app builds keep using the
    /// CLI item and cannot accidentally claim the release app's Keychain entry.
    public static var shouldUseCompanionCredential: Bool {
        shouldUseCompanionCredential(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            teamIdentifier: currentSigningTeamIdentifier()
        )
    }

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
        try save(secret: secret, boardID: boardID, service: Self.legacyService)
    }

    /// Loads the credential created by USB provisioning. The installed app calls
    /// this only after showing its own explanation and receiving an explicit user
    /// action, because macOS may need to authorize the different signed client.
    public func authorizeCompanion(boardID: String) throws -> Data {
        let secret = try load(boardID: boardID, service: Self.legacyService)
        try save(secret: secret, boardID: boardID, service: Self.companionService)
        return secret
    }

    /// Loads the app-owned copy. Once the one-time migration has completed, the
    /// stable Developer ID identity can read this item on later launches without
    /// revisiting the CLI-owned credential.
    public func loadForCompanion(boardID: String) throws -> Data {
        try load(boardID: boardID, service: Self.companionService)
    }

    private func save(secret: Data, boardID: String, service: String) throws {
        guard Self.valid(boardID: boardID) else { throw PairingError.invalidBoardID }
        guard secret.count == 32 else { throw PairingError.invalidSecret }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: boardID,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: secret,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw PairingError.keychain(updateStatus) }

        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw PairingError.keychain(status) }
    }

    public func load(boardID: String) throws -> Data {
        try load(boardID: boardID, service: Self.legacyService)
    }

    private func load(boardID: String, service: String) throws -> Data {
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

    static func valid(boardID: String) -> Bool {
        guard (1...80).contains(boardID.count) else { return false }
        return boardID.allSatisfy { $0.isLetter || $0.isNumber || ".-_".contains($0) }
    }

    static func shouldUseCompanionCredential(
        bundleIdentifier: String?,
        teamIdentifier: String?
    ) -> Bool {
        bundleIdentifier == companionBundleIdentifier && teamIdentifier == companionTeamIdentifier
    }

    private static func currentSigningTeamIdentifier() -> String? {
        var code: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            SecCSFlags(),
            &code
        )
        guard createStatus == errSecSuccess, let code else { return nil }
        var signingInformation: CFDictionary?
        let status = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard status == errSecSuccess,
              let dictionary = signingInformation as? [String: Any]
        else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
