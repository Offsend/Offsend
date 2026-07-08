import DetectionCore
import Foundation
import MaskingCore

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
