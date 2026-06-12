import XCTest
@testable import StorageCore

final class HookedRepositoryTests: XCTestCase {
    func testAppSettingsDefaultsHookedRepositoriesToEmpty() {
        XCTAssertTrue(AppSettings.default.hookedRepositories.isEmpty)
    }

    func testAppSettingsDecodesMissingHookedRepositoriesAsEmpty() throws {
        let json = """
        {
          "hasCompletedOnboarding": false,
          "protectionEnabled": true,
          "clipboardMonitoringEnabled": true,
          "launchAtLogin": false,
          "defaultNoRiskAction": "pasteOriginal",
          "enabledDetectors": ["email"],
          "mappingTTL": "oneHour",
          "restoreBehavior": "copyToClipboard",
          "preserveOriginalClipboard": true,
          "analyticsOptIn": false,
          "allowPasteOriginalForCriticalSecrets": false,
          "directoryCheckDisabledRuleIDs": [],
          "directoryCheckConfirmFix": true,
          "directoryCheckExtraSkippedDirectories": [],
          "directoryWatchEnabled": false,
          "watchedDirectories": [],
          "directoryWatchNotifyOnDegrade": true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertTrue(settings.hookedRepositories.isEmpty)
    }
}
