import Foundation
import Security

public enum HuggingFaceTokenStoreError: Error, Equatable, Sendable {
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
}

extension HuggingFaceTokenStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .keychainReadFailed(let status):
            return StorageCoreStrings.storageErrorKeychainReadFailed(status)
        case .keychainWriteFailed(let status):
            return StorageCoreStrings.storageErrorKeychainWriteFailed(status)
        case .keychainDeleteFailed(let status):
            return StorageCoreStrings.storageErrorKeychainWriteFailed(status)
        }
    }
}

public final class HuggingFaceTokenStore: Sendable {
    public static let shared = HuggingFaceTokenStore()

    private let service = "io.offsend"
    private let account = "huggingface-access-token"

    public init() {}

    /// Shows enough of a Hugging Face token to identify it without exposing the full secret.
    public static func maskedPreview(for token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "••••" }

        let prefixLength = trimmed.hasPrefix("hf_") ? 3 : min(4, trimmed.count)
        let suffixLength = 4
        guard trimmed.count > prefixLength + suffixLength else {
            return String(repeating: "•", count: min(trimmed.count, 8))
        }

        return "\(trimmed.prefix(prefixLength))...\(trimmed.suffix(suffixLength))"
    }

    public func loadToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw HuggingFaceTokenStoreError.keychainReadFailed(status)
        }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteToken()
            return
        }

        guard let data = trimmed.data(using: .utf8) else { return }

        if (try? loadToken()) != nil {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw HuggingFaceTokenStoreError.keychainWriteFailed(status)
            }
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw HuggingFaceTokenStoreError.keychainWriteFailed(status)
        }
    }

    public func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HuggingFaceTokenStoreError.keychainDeleteFailed(status)
        }
    }
}
