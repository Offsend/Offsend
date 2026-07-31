import Foundation
import Security

/// Stores device id and signed license token in Keychain (not in app documents).
public struct LicenseKeychainSecrets: Codable, Equatable, Sendable {
    public var deviceId: UUID
    public var signedLicenseToken: String?
    public var lastValidationAt: Date?

    public init(deviceId: UUID, signedLicenseToken: String? = nil, lastValidationAt: Date? = nil) {
        self.deviceId = deviceId
        self.signedLicenseToken = signedLicenseToken
        self.lastValidationAt = lastValidationAt
    }
}

public enum LicenseKeychainError: LocalizedError, Equatable {
    case unexpectedData
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Unexpected data in license keychain item."
        case .keychain(let status):
            return "Keychain error (\(status))."
        }
    }
}

public final class LicenseKeychainStore: @unchecked Sendable {
    private let service = "io.offsend.app.license"
    private let account = "secrets.v1"

    public init() {}

    public func load() throws -> LicenseKeychainSecrets? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw LicenseKeychainError.keychain(status) }
        guard let data = result as? Data else { throw LicenseKeychainError.unexpectedData }
        return try JSONDecoder().decode(LicenseKeychainSecrets.self, from: data)
    }

    public func save(_ secrets: LicenseKeychainSecrets) throws {
        let data = try JSONEncoder().encode(secrets)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LicenseKeychainError.keychain(status) }
    }

    public func clearLicenseToken() throws {
        guard var secrets = try load() else { return }
        secrets.signedLicenseToken = nil
        try save(secrets)
    }

    public func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
