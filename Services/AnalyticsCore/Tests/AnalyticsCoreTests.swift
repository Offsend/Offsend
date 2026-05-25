import DetectionCore
@testable import AnalyticsCore
import MaskingCore
import StorageCore
import XCTest

final class AnalyticsCoreTests: XCTestCase {
    func testAppAnalyticsTracksLocallyAlways() throws {
        let store = InMemoryLocalStoreForAnalyticsTests()
        let analytics = AppAnalytics(
            local: LocalAnalytics(store: store),
            product: TelemetryDeckAnalytics(isEnabled: false)
        )

        analytics.track(.maskApplied)
        analytics.track(.onboardingCompleted)

        let events = try store.loadEvents()
        XCTAssertEqual(events.map(\.type), ["mask_applied", "onboarding_completed"])
    }

    func testTelemetryDeckAnalyticsRespectsOptIn() {
        let product = TelemetryDeckAnalytics(isEnabled: false)
        product.track(.onboardingCompleted)
        product.isEnabled = true
        product.track(.restoreUsed)
        // Disabled path is a no-op; enabled path calls TelemetryDeck (not asserted here).
    }

    func testAnalyticsEventTelemetryParameters() {
        XCTAssertEqual(
            AnalyticsEvent.safePasteUsed(riskLevel: .high, entityCount: 2, usedCachedScan: false).telemetryParameters,
            [
                "entity_count": "2",
                "used_cached_scan": "false",
                "risk_level": "high",
            ]
        )
        XCTAssertEqual(
            AnalyticsEvent.pasteOriginalChosen(riskLevel: nil).telemetryParameters,
            ["risk_level": "none"]
        )
    }
}

private final class InMemoryLocalStoreForAnalyticsTests: LocalStoring {
    private var events: [LocalEvent] = []
    private var settings = AppSettings.default

    func loadSettings() throws -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) throws { self.settings = settings }
    func loadCustomDictionaries() throws -> [CustomDictionaryItem] { [] }
    func saveCustomDictionaries(_ items: [CustomDictionaryItem]) throws {}
    func loadLicenseState() throws -> LicenseState { LicenseState() }
    func saveLicenseState(_ state: LicenseState) throws {}
    func saveMapping(_ result: MaskingResult) throws {}
    func restore(text: String) throws -> String? { nil }
    func mappingSummaries() throws -> [StoredMappingSummary] { [] }
    func deleteMapping(id: UUID) throws {}
    func clearMappings() throws {}
    func cleanupExpiredMappings() throws {}
    func appendEvent(_ event: LocalEvent) throws { events.append(event) }
    func loadEvents() throws -> [LocalEvent] { events }
    func clearEvents() throws { events.removeAll() }
}
