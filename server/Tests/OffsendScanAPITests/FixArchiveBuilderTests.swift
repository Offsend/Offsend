import Foundation
import XCTest
@testable import OffsendScanAPI

final class FixArchiveBuilderTests: XCTestCase {
    func testFixFilesReadsFromReportJSON() {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true, "claude-ignore": false],
            exposedPatterns: [],
            exposedFiles: 0,
            fixFiles: [
                ["path": ".claudeignore", "contents": "# offsend\n.env*\n"],
            ]
        )
        let files = FixArchiveBuilder.fixFiles(reportJSON: json)
        XCTAssertEqual(files.map(\.path), [".claudeignore"])
        XCTAssertTrue(files[0].contents.contains(".env*"))
    }

    func testFixFilesReturnsEmptyWhenNothingToFix() {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true],
            exposedPatterns: [],
            exposedFiles: 0,
            fixFiles: []
        )
        XCTAssertTrue(FixArchiveBuilder.fixFiles(reportJSON: json).isEmpty)
    }

    func testFixFilesReturnsEmptyForInvalidJSON() {
        XCTAssertTrue(FixArchiveBuilder.fixFiles(reportJSON: "not json").isEmpty)
    }

    func testFixFilesReturnsEmptyWhenFieldMissing() {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": false],
            exposedPatterns: [],
            exposedFiles: 0,
            includeFixFilesKey: false
        )
        XCTAssertTrue(FixArchiveBuilder.fixFiles(reportJSON: json).isEmpty)
    }
}
