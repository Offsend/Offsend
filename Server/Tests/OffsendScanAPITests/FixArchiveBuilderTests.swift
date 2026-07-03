import Foundation
import XCTest
@testable import OffsendScanAPI

final class FixArchiveBuilderTests: XCTestCase {
    func testFixFilesIncludesMissingIgnoreFile() {
        // No exposed patterns: only the missing gating file is generated, the
        // present one is left untouched.
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true, "claude-ignore": false],
            exposedPatterns: [],
            exposedFiles: 0
        )
        let files = FixArchiveBuilder.fixFiles(reportJSON: json)
        let paths = files.map(\.path)

        XCTAssertTrue(paths.contains(".claudeignore"))
        XCTAssertFalse(paths.contains(".cursorignore"))
        XCTAssertTrue(files.contains { $0.path == ".claudeignore" && !$0.contents.isEmpty })
    }

    func testFixFilesRefreshesPresentIgnoreFilesWhenPatternsExposed() {
        // File is present but patterns still leak → ship a full-coverage replacement.
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true],
            exposedPatterns: [
                ["id": "env-files", "severity": "required", "category": "secret", "count": 2],
            ]
        )
        let files = FixArchiveBuilder.fixFiles(reportJSON: json)
        let cursor = files.first { $0.path == ".cursorignore" }

        XCTAssertNotNil(cursor)
        XCTAssertTrue(cursor?.contents.contains(".env*") == true)
    }

    func testFixFilesReturnsEmptyWhenNothingToFix() {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true],
            exposedPatterns: [],
            exposedFiles: 0
        )
        XCTAssertTrue(FixArchiveBuilder.fixFiles(reportJSON: json).isEmpty)
    }

    func testFixFilesReturnsEmptyForInvalidJSON() {
        XCTAssertTrue(FixArchiveBuilder.fixFiles(reportJSON: "not json").isEmpty)
    }

    func testFixFilesIncludesMissingGatingFile() {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": false],
            exposedPatterns: [],
            exposedFiles: 0
        )
        XCTAssertFalse(FixArchiveBuilder.fixFiles(reportJSON: json).isEmpty)
    }
}
