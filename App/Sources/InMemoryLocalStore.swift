import DetectionCore
import Foundation
import MaskingCore
import StorageCore

final class InMemoryLocalStore: LocalStoring {
    private static let maxStoredEvents = 2_000

    private var settings = AppSettings.default
    private var dictionaries: [CustomDictionaryItem] = []
    private var mappings: [MaskingResult] = []
    private var events: [LocalEvent] = []
    private var license = LicenseState()
    private var installedAIModels: [InstalledAIModel] = []
    private let maskingEngine = MaskingEngine()

    func loadSettings() throws -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) throws { self.settings = settings }
    func loadCustomDictionaries() throws -> [CustomDictionaryItem] { dictionaries }
    func saveCustomDictionaries(_ items: [CustomDictionaryItem]) throws { dictionaries = items }
    func saveMapping(_ result: MaskingResult) throws {
        guard result.shouldPersist else { return }
        mappings.removeAll { $0.id == result.id }
        mappings.append(result)
    }

    func restore(text: String) throws -> String? {
        cleanupExpired()
        guard let mapping = mappings.last(where: { result in result.mapping.keys.contains(where: text.contains) }) else { return nil }
        return maskingEngine.restore(text: text, mapping: mapping.mapping)
    }

    func mappingSummaries() throws -> [StoredMappingSummary] {
        cleanupExpired()
        return mappings.map { StoredMappingSummary(id: $0.id, createdAt: $0.createdAt, expiresAt: $0.expiresAt, placeholderCount: $0.mapping.count) }
    }

    func deleteMapping(id: UUID) throws { mappings.removeAll { $0.id == id } }
    func clearMappings() throws { mappings.removeAll() }
    func cleanupExpiredMappings() throws { cleanupExpired() }
    func appendEvent(_ event: LocalEvent) throws {
        events.append(event)
        if events.count > Self.maxStoredEvents {
            events = Array(events.suffix(Self.maxStoredEvents))
        }
    }
    func loadEvents() throws -> [LocalEvent] { events }
    func clearEvents() throws { events.removeAll() }
    func loadLicenseState() throws -> LicenseState { license }
    func saveLicenseState(_ state: LicenseState) throws { license = state }
    func loadInstalledAIModels() throws -> [InstalledAIModel] { installedAIModels }
    func saveInstalledAIModels(_ models: [InstalledAIModel]) throws { installedAIModels = models }

    private func cleanupExpired() {
        let now = Date()
        mappings.removeAll { result in
            guard let expiresAt = result.expiresAt else { return false }
            return expiresAt <= now
        }
    }
}
