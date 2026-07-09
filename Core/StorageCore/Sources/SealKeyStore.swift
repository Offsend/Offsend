import Foundation

/// Stores the user-managed AES-256 seal key (separate from mapping master key).
public protocol SealKeyStoring: Sendable {
    /// Returns the 32-byte key, or `nil` if none is configured.
    func loadKey() throws -> Data?
    /// Persists a 32-byte key. Replaces any existing key.
    func saveKey(_ data: Data) throws
    /// Removes the stored key.
    func deleteKey() throws
    /// Whether a key is currently stored (does not load key material).
    var hasKey: Bool { get }
}

#if canImport(Security)
import Security

/// Keychain-backed seal key store for the macOS app.
/// Account is distinct from `KeychainKeyProvider` (`mapping-master-key`).
public final class KeychainSealKeyStore: SealKeyStoring, @unchecked Sendable {
    public static let keyByteCount = 32

    private let service: String
    private let account: String

    public init(service: String = "io.offsend", account: String = "seal-key") {
        self.service = service
        self.account = account
    }

    public var hasKey: Bool {
        (try? loadKey()) != nil
    }

    public func loadKey() throws -> Data? {
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
        guard status == errSecSuccess else { throw StorageError.keychainReadFailed(status) }
        let data = result as? Data
        guard let data, data.count == Self.keyByteCount else {
            throw StorageError.keychainReadFailed(errSecDecode)
        }
        return data
    }

    public func saveKey(_ data: Data) throws {
        guard data.count == Self.keyByteCount else {
            throw StorageError.keyGenerationFailed(errSecParam)
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw StorageError.keychainWriteFailed(status) }
    }

    public func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else { throw StorageError.keychainWriteFailed(status) }
    }
}
#endif

/// In-memory seal key store for tests and CLI/Linux (no Keychain).
public final class InMemorySealKeyStore: SealKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data?

    public init(key: Data? = nil) {
        self.key = key
    }

    public var hasKey: Bool {
        lock.lock()
        defer { lock.unlock() }
        return key != nil
    }

    public func loadKey() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return key
    }

    public func saveKey(_ data: Data) throws {
        guard data.count == 32 else {
            throw SealKeyStoreError.invalidKeyLength(data.count)
        }
        lock.lock()
        defer { lock.unlock() }
        key = data
    }

    public func deleteKey() throws {
        lock.lock()
        defer { lock.unlock() }
        key = nil
    }
}

public enum SealKeyStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidKeyLength(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidKeyLength(let count):
            return "Seal key must be 32 bytes, got \(count)."
        }
    }
}
