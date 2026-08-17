import Foundation
import Security

public enum XAIAPIKeyError: Error, LocalizedError, Sendable {
    case invalidKey
    case notFound
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            "Enter a valid xAI API key. It should start with xai- and contain no spaces."
        case .notFound:
            "No xAI API key is stored in Keychain."
        case let .keychain(status):
            "Keychain operation failed with status \(status)."
        }
    }
}

public protocol XAIAPIKeyProviding: Sendable {
    func loadAPIKey() throws -> String
}

public struct XAIAPIKeyStore: XAIAPIKeyProviding, Sendable {
    static let service = "com.iloapps.iloboard.menu.xai-api-key.v1"
    static let account = "default"

    public init() {}

    public var isConfigured: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public func saveAPIKey(_ value: String) throws {
        let key = try Self.normalized(value)
        guard let data = key.data(using: .utf8) else { throw XAIAPIKeyError.invalidKey }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrLabel as String: "ILO Board xAI API key",
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw XAIAPIKeyError.keychain(updateStatus)
        }

        var item = query
        updateAttributes.forEach { item[$0.key] = $0.value }
        item[kSecAttrSynchronizable as String] = false
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw XAIAPIKeyError.keychain(addStatus) }
    }

    public func loadAPIKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw XAIAPIKeyError.notFound }
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            throw XAIAPIKeyError.keychain(status)
        }
        return try Self.normalized(key)
    }

    public func removeAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw XAIAPIKeyError.keychain(status)
        }
    }

    static func normalized(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("xai-"),
              (20...256).contains(key.count),
              key.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && scalar.value >= 0x21 && scalar.value <= 0x7e
              })
        else {
            throw XAIAPIKeyError.invalidKey
        }
        return key
    }
}
