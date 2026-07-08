import DetectionCore
import Foundation
import MaskingCore

/// Plain JSON store for CLI and non-Apple platforms. Settings, dictionaries, events, and
/// license state are stored as unencrypted JSON files under `LocalStoreDirectory`.
/// Mapping persistence is intentionally unsupported (no-op).
public final class FileLocalStore: LocalStoring {
    private let directory: URL
    private let codec = LocalStoreJSONCodec()

    public init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        let resolvedDirectory = directory ?? LocalStoreDirectory.defaultURL(fileManager: fileManager)
        try fileManager.createDirectory(at: resolvedDirectory, withIntermediateDirectories: true)
        self.directory = resolvedDirectory
    }

    public func loadSettings() throws -> AppSettings {
        try codec.load(AppSettings.self, from: files.settings) ?? .default
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try codec.save(settings, to: files.settings)
    }

    public func loadCustomDictionaries() throws -> [CustomDictionaryItem] {
        try codec.load([CustomDictionaryItem].self, from: files.customDictionaries) ?? []
    }

    public func saveCustomDictionaries(_ items: [CustomDictionaryItem]) throws {
        try codec.save(items, to: files.customDictionaries)
    }

    public func saveMapping(_ result: MaskingResult) throws {}

    public func restore(text: String) throws -> String? { nil }

    public func mappingSummaries() throws -> [StoredMappingSummary] { [] }

    public func deleteMapping(id: UUID) throws {}

    public func clearMappings() throws {}

    public func cleanupExpiredMappings() throws {}

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
}
