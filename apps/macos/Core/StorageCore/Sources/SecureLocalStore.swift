#if canImport(Security)
import CryptoKit
import DetectionCore
import Foundation
import MaskingCore
import Security

public final class SecureLocalStore: LocalStoring {
    private let directory: URL
    private let codec = LocalStoreJSONCodec()
    private let loadMasterKey: () throws -> Data
    private let maskingEngine: TextMasking

    public init(
        directory: URL? = nil,
        keyProvider: KeychainKeyProvider = KeychainKeyProvider(),
        maskingEngine: TextMasking
    ) throws {
        self.directory = directory ?? LocalStoreDirectory.defaultURL()
        self.loadMasterKey = { try keyProvider.masterKey() }
        self.maskingEngine = maskingEngine
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Test initializer. Production code uses the Keychain-backed initializer.
    init(directory: URL, masterKey: Data, maskingEngine: TextMasking) throws {
        self.directory = directory
        self.loadMasterKey = { masterKey }
        self.maskingEngine = maskingEngine
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func loadSettings() throws -> AppSettings {
        try codec.load(AppSettings.self, from: files.settings) ?? .default
    }

    public func saveSettings(_ settings: AppSettings) throws {
        let previous = try loadSettings()
        try codec.save(settings, to: files.settings)
        guard previous.encryptSensitiveTerms != settings.encryptSensitiveTerms else { return }
        _ = try loadCustomDictionaries()
    }

    public func loadCustomDictionaries() throws -> [CustomDictionaryItem] {
        let stored = try codec.load([StoredCustomDictionaryItem].self, from: files.customDictionaries) ?? []
        let items = try stored.map { try plaintextItem($0) }
        let seal = try shouldSealSensitiveTerms()
        if stored.contains(where: { storedNeedsRewrite($0, seal: seal) }) {
            try saveCustomDictionaries(items)
        }
        return items
    }

    public func saveCustomDictionaries(_ items: [CustomDictionaryItem]) throws {
        let seal = try shouldSealSensitiveTerms()
        let stored: [StoredCustomDictionaryItem] = try items.map { item in
            guard seal, item.kind == .sensitiveTerm else {
                return StoredCustomDictionaryItem(item)
            }
            return StoredCustomDictionaryItem(item, sealedValue: try sealSensitiveTerm(item.value))
        }
        try codec.save(stored, to: files.customDictionaries)
    }

    public func saveMapping(_ result: MaskingResult) throws {
        guard result.shouldPersist else { return }
        var mappings = try loadStoredMappings()
        let payload = try codec.encoder.encode(result.mapping)
        let encrypted = try encrypt(payload)
        mappings.removeAll { $0.id == result.id }
        mappings.append(StoredMapping(id: result.id, createdAt: result.createdAt, expiresAt: result.expiresAt, encryptedPayload: encrypted))
        try codec.save(mappings, to: files.mappings)
    }

    public func restore(text: String) throws -> String? {
        try cleanupExpiredMappings()
        for mapping in try loadStoredMappings().sorted(by: { $0.createdAt > $1.createdAt }) {
            let decrypted = try decrypt(mapping.encryptedPayload)
            let dictionary = try codec.decoder.decode([String: String].self, from: decrypted)
            guard dictionary.keys.contains(where: { text.contains($0) }) else { continue }
            return maskingEngine.restore(text: text, mapping: dictionary)
        }
        return nil
    }

    public func mappingSummaries() throws -> [StoredMappingSummary] {
        try cleanupExpiredMappings()
        return try loadStoredMappings().map { mapping in
            let decrypted = try decrypt(mapping.encryptedPayload)
            let dictionary = try codec.decoder.decode([String: String].self, from: decrypted)
            return StoredMappingSummary(id: mapping.id, createdAt: mapping.createdAt, expiresAt: mapping.expiresAt, placeholderCount: dictionary.count)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public func deleteMapping(id: UUID) throws {
        var mappings = try loadStoredMappings()
        mappings.removeAll { $0.id == id }
        try codec.save(mappings, to: files.mappings)
    }

    public func clearMappings() throws {
        try codec.save([StoredMapping](), to: files.mappings)
    }

    public func cleanupExpiredMappings() throws {
        let now = Date()
        var mappings = try loadStoredMappings()
        mappings.removeAll { mapping in
            guard let expiresAt = mapping.expiresAt else { return false }
            return expiresAt <= now
        }
        try codec.save(mappings, to: files.mappings)
    }

    public func appendEvent(_ event: LocalEvent) throws {
        var events = try loadEvents()
        events.append(event)
        try codec.save(Array(events.suffix(2_000)), to: files.events)
    }

    public func loadEvents() throws -> [LocalEvent] {
        try codec.load([LocalEvent].self, from: files.events) ?? []
    }

    public func clearEvents() throws {
        try codec.save([LocalEvent](), to: files.events)
    }

    public func loadLicenseState() throws -> LicenseState {
        try codec.load(LicenseState.self, from: files.license) ?? LicenseState()
    }

    public func saveLicenseState(_ state: LicenseState) throws {
        try codec.save(state, to: files.license)
    }

    private var files: LocalStoreFiles {
        LocalStoreFiles(directory: directory)
    }

    private func loadStoredMappings() throws -> [StoredMapping] {
        try codec.load([StoredMapping].self, from: files.mappings) ?? []
    }

    private func encrypt(_ data: Data) throws -> Data {
        let key = SymmetricKey(data: try loadMasterKey())
        return try AES.GCM.seal(data, using: key).combined ?? Data()
    }

    private func decrypt(_ data: Data) throws -> Data {
        let key = SymmetricKey(data: try loadMasterKey())
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    private func sealSensitiveTerm(_ plaintext: String) throws -> String {
        let key = SymmetricKey(data: try loadMasterKey())
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        } catch {
            throw StorageError.sensitiveTermProtectionFailed
        }
        guard let combined = box.combined else {
            throw StorageError.sensitiveTermProtectionFailed
        }
        return combined.base64EncodedString()
    }

    private func openSensitiveTerm(_ sealed: String) throws -> String {
        let key = SymmetricKey(data: try loadMasterKey())
        guard let data = Data(base64Encoded: sealed) else {
            throw StorageError.sensitiveTermProtectionFailed
        }
        do {
            let plain = try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: key)
            guard let string = String(data: plain, encoding: .utf8) else {
                throw StorageError.sensitiveTermProtectionFailed
            }
            return string
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.sensitiveTermProtectionFailed
        }
    }

    private func shouldSealSensitiveTerms() throws -> Bool {
        try loadSettings().encryptSensitiveTerms
    }

    private func storedNeedsRewrite(_ stored: StoredCustomDictionaryItem, seal: Bool) -> Bool {
        stored.kind == .sensitiveTerm && (stored.valueSealed == true) != seal
    }

    private func plaintextItem(_ stored: StoredCustomDictionaryItem) throws -> CustomDictionaryItem {
        let value: String
        if stored.kind == .sensitiveTerm, stored.valueSealed == true {
            value = try openSensitiveTerm(stored.value)
        } else {
            value = stored.value
        }
        return CustomDictionaryItem(id: stored.id, kind: stored.kind, value: value, createdAt: stored.createdAt)
    }
}

private struct StoredCustomDictionaryItem: Codable, Equatable {
    var id: UUID
    var kind: CustomDictionaryKind
    var value: String
    var createdAt: Date
    var valueSealed: Bool?

    init(_ item: CustomDictionaryItem, sealedValue: String? = nil) {
        id = item.id
        kind = item.kind
        createdAt = item.createdAt
        if let sealedValue {
            value = sealedValue
            valueSealed = true
        } else {
            value = item.value
            valueSealed = nil
        }
    }
}

private struct StoredMapping: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let expiresAt: Date?
    let encryptedPayload: Data
}

public final class KeychainKeyProvider {
    private let service = "io.offsend"
    private let account = "mapping-master-key"

    public init() {}

    public func masterKey() throws -> Data {
        if let existing = try readKey() {
            return existing
        }

        var key = Data(count: 32)
        let status = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw StorageError.keyGenerationFailed(status)
        }

        try saveKey(key)
        return key
    }

    private func readKey() throws -> Data? {
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
        return result as? Data
    }

    private func saveKey(_ key: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw StorageError.keychainWriteFailed(status) }
    }
}

public enum StorageError: LocalizedError {
    case keyGenerationFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case sensitiveTermProtectionFailed

    public var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let status):
            return StorageCoreStrings.storageErrorKeyGenerationFailed(status)
        case .keychainReadFailed(let status):
            return StorageCoreStrings.storageErrorKeychainReadFailed(status)
        case .keychainWriteFailed(let status):
            return StorageCoreStrings.storageErrorKeychainWriteFailed(status)
        case .sensitiveTermProtectionFailed:
            return StorageCoreStrings.storageErrorSensitiveTermProtectionFailed
        }
    }
}
#endif
