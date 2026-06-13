import CryptoKit
import DetectionCore
import Foundation
import MaskingCore
import Security

public protocol LocalStoring {
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
    func loadCustomDictionaries() throws -> [CustomDictionaryItem]
    func saveCustomDictionaries(_ items: [CustomDictionaryItem]) throws
    func saveMapping(_ result: MaskingResult) throws
    func restore(text: String) throws -> String?
    func mappingSummaries() throws -> [StoredMappingSummary]
    func deleteMapping(id: UUID) throws
    func clearMappings() throws
    func cleanupExpiredMappings() throws
    func appendEvent(_ event: LocalEvent) throws
    func loadEvents() throws -> [LocalEvent]
    func clearEvents() throws
    func loadLicenseState() throws -> LicenseState
    func saveLicenseState(_ state: LicenseState) throws
}

public final class SecureLocalStore: LocalStoring {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let keyProvider: KeychainKeyProvider

    public init(directory: URL? = nil, keyProvider: KeychainKeyProvider = KeychainKeyProvider()) throws {
        self.directory = directory ?? Self.defaultDirectory()
        self.keyProvider = keyProvider
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func loadSettings() throws -> AppSettings {
        try load(AppSettings.self, from: files.settings) ?? .default
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try save(settings, to: files.settings)
    }

    public func loadCustomDictionaries() throws -> [CustomDictionaryItem] {
        try load([CustomDictionaryItem].self, from: files.customDictionaries) ?? []
    }

    public func saveCustomDictionaries(_ items: [CustomDictionaryItem]) throws {
        try save(items, to: files.customDictionaries)
    }

    public func saveMapping(_ result: MaskingResult) throws {
        guard result.shouldPersist else { return }
        var mappings = try loadStoredMappings()
        let payload = try encoder.encode(result.mapping)
        let encrypted = try encrypt(payload)
        mappings.removeAll { $0.id == result.id }
        mappings.append(StoredMapping(id: result.id, createdAt: result.createdAt, expiresAt: result.expiresAt, encryptedPayload: encrypted))
        try save(mappings, to: files.mappings)
    }

    public func restore(text: String) throws -> String? {
        try cleanupExpiredMappings()
        let engine = MaskingEngine()
        for mapping in try loadStoredMappings().sorted(by: { $0.createdAt > $1.createdAt }) {
            let decrypted = try decrypt(mapping.encryptedPayload)
            let dictionary = try decoder.decode([String: String].self, from: decrypted)
            guard dictionary.keys.contains(where: { text.contains($0) }) else { continue }
            return engine.restore(text: text, mapping: dictionary)
        }
        return nil
    }

    public func mappingSummaries() throws -> [StoredMappingSummary] {
        try cleanupExpiredMappings()
        return try loadStoredMappings().map { mapping in
            let decrypted = try decrypt(mapping.encryptedPayload)
            let dictionary = try decoder.decode([String: String].self, from: decrypted)
            return StoredMappingSummary(id: mapping.id, createdAt: mapping.createdAt, expiresAt: mapping.expiresAt, placeholderCount: dictionary.count)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public func deleteMapping(id: UUID) throws {
        var mappings = try loadStoredMappings()
        mappings.removeAll { $0.id == id }
        try save(mappings, to: files.mappings)
    }

    public func clearMappings() throws {
        try save([StoredMapping](), to: files.mappings)
    }

    public func cleanupExpiredMappings() throws {
        let now = Date()
        var mappings = try loadStoredMappings()
        mappings.removeAll { mapping in
            guard let expiresAt = mapping.expiresAt else { return false }
            return expiresAt <= now
        }
        try save(mappings, to: files.mappings)
    }

    public func appendEvent(_ event: LocalEvent) throws {
        var events = try loadEvents()
        events.append(event)
        try save(events.suffix(2_000), to: files.events)
    }

    public func loadEvents() throws -> [LocalEvent] {
        try load([LocalEvent].self, from: files.events) ?? []
    }

    public func clearEvents() throws {
        try save([LocalEvent](), to: files.events)
    }

    public func loadLicenseState() throws -> LicenseState {
        try load(LicenseState.self, from: files.license) ?? LicenseState()
    }

    public func saveLicenseState(_ state: LicenseState) throws {
        try save(state, to: files.license)
    }

    private var files: StoreFiles {
        StoreFiles(directory: directory)
    }

    private func loadStoredMappings() throws -> [StoredMapping] {
        try load([StoredMapping].self, from: files.mappings) ?? []
    }

    private func encrypt(_ data: Data) throws -> Data {
        let key = SymmetricKey(data: try keyProvider.masterKey())
        return try AES.GCM.seal(data, using: key).combined ?? Data()
    }

    private func decrypt(_ data: Data) throws -> Data {
        let key = SymmetricKey(data: try keyProvider.masterKey())
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Offsend", isDirectory: true)
    }
}

private struct StoreFiles {
    let directory: URL

    var settings: URL { directory.appendingPathComponent("settings.json") }
    var customDictionaries: URL { directory.appendingPathComponent("custom_dictionaries.json") }
    var mappings: URL { directory.appendingPathComponent("mappings.sqlite.json") }
    var events: URL { directory.appendingPathComponent("local_events.json") }
    var license: URL { directory.appendingPathComponent("license.json") }
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

    public var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let status):
            return StorageCoreStrings.storageErrorKeyGenerationFailed(status)
        case .keychainReadFailed(let status):
            return StorageCoreStrings.storageErrorKeychainReadFailed(status)
        case .keychainWriteFailed(let status):
            return StorageCoreStrings.storageErrorKeychainWriteFailed(status)
        }
    }
}
