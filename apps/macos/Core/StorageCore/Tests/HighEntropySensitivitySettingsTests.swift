import DetectionCore
import XCTest
@testable import StorageCore

final class HighEntropySensitivitySettingsTests: XCTestCase {
    func testAppSettingsDefaultsToNormal() {
        XCTAssertEqual(AppSettings.default.highEntropySensitivity, .normal)
        XCTAssertFalse(AppSettings.default.encryptSensitiveTerms)
        XCTAssertEqual(DetectionOptions.default.highEntropySensitivity, .normal)
    }

    func testAppSettingsDecodesMissingSensitivityAsNormal() throws {
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
          "allowPasteOriginalForCriticalSecrets": false
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.highEntropySensitivity, .normal)
        XCTAssertFalse(settings.encryptSensitiveTerms)
    }

    func testAppSettingsRoundTripsSensitivity() throws {
        for level in HighEntropySensitivity.allCases {
            var settings = AppSettings.default
            settings.highEntropySensitivity = level
            let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(decoded.highEntropySensitivity, level)
        }
    }

    func testSensitivityRawValuesMatchRustNames() {
        XCTAssertEqual(HighEntropySensitivity.allCases.map(\.rawValue), ["strict", "normal", "relaxed"])
    }
}
