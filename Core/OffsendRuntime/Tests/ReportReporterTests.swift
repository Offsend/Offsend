import Foundation
import XCTest
@testable import OffsendRuntime

final class ReportReporterTests: XCTestCase {
    private func makeReport(
        scanComplete: Bool = true,
        ignoreFiles: [ReportIgnoreFilePresence] = [
            ReportIgnoreFilePresence(ruleID: "git-ignore", present: true),
            ReportIgnoreFilePresence(ruleID: "cursor-ignore", present: false)
        ],
        exposedPatterns: [ReportExposedPattern] = [
            ReportExposedPattern(patternID: "env-files", severity: "required", category: "secret", count: 3)
        ],
        totalExposedFiles: Int = 3,
        errorIDs: [String] = []
    ) -> PrivacyReport {
        PrivacyReport(
            rulesetVersion: "abc123",
            scanComplete: scanComplete,
            ignoreFiles: ignoreFiles,
            exposedPatterns: exposedPatterns,
            totalExposedFiles: totalExposedFiles,
            errorIDs: errorIDs
        )
    }

    private func decode(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    func testEmitsSchemaToolVersionAndGeneratedAt() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let json = ReportReporter().renderJSON(makeReport(), toolVersion: "1.2.3", generatedAt: date)
        let object = try decode(json)

        XCTAssertEqual(object["schemaVersion"] as? Int, ReportReporter.schemaVersion)
        XCTAssertEqual(object["toolVersion"] as? String, "1.2.3")
        XCTAssertEqual(object["rulesetVersion"] as? String, "abc123")
        XCTAssertEqual(object["generatedAt"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(object["scanComplete"] as? Bool, true)
    }

    func testIgnoreFilesAreEmittedAsPresenceMap() throws {
        let json = ReportReporter().renderJSON(makeReport(), toolVersion: "1.0.0", generatedAt: Date())
        let object = try decode(json)
        let present = try XCTUnwrap(object["ignoreFilesPresent"] as? [String: Bool])

        XCTAssertEqual(present["git-ignore"], true)
        XCTAssertEqual(present["cursor-ignore"], false)
    }

    func testTotalsCountExposedFilesAndPatternTypes() throws {
        let report = makeReport(
            exposedPatterns: [
                ReportExposedPattern(patternID: "env-files", severity: "required", category: "secret", count: 3),
                ReportExposedPattern(patternID: "pem-files", severity: "required", category: "secret", count: 1)
            ],
            totalExposedFiles: 4
        )
        let json = ReportReporter().renderJSON(report, toolVersion: "1.0.0", generatedAt: Date())
        let object = try decode(json)
        let totals = try XCTUnwrap(object["totals"] as? [String: Any])

        XCTAssertEqual(totals["exposedFiles"] as? Int, 4)
        XCTAssertEqual(totals["exposedPatternTypes"] as? Int, 2)
    }

    func testExposedPatternsCarryCategory() throws {
        let report = makeReport(
            exposedPatterns: [
                ReportExposedPattern(patternID: "local-databases", severity: "informational", category: "pii", count: 2)
            ]
        )
        let json = ReportReporter().renderJSON(report, toolVersion: "1.0.0", generatedAt: Date())
        let object = try decode(json)
        let patterns = try XCTUnwrap(object["exposedPatterns"] as? [[String: Any]])

        XCTAssertEqual(patterns.first?["category"] as? String, "pii")
    }
}
