import Foundation
import XCTest
@testable import OffsendScanAPI

final class FixArchiveBuilderTests: XCTestCase {
    func testBuildsArchiveWithMissingIgnoreFileAndReadme() throws {
        // No exposed patterns: only the missing gating file is generated, the
        // present one is left untouched.
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true, "claude-ignore": false],
            exposedPatterns: [],
            exposedFiles: 0
        )
        let data = try XCTUnwrap(
            FixArchiveBuilder.makeArchive(reportJSON: json, repoURL: "https://github.com/org/repo")
        )
        let text = zipText(data)

        XCTAssertTrue(hasZipSignatures(data))
        XCTAssertTrue(text.contains(".claudeignore"))
        XCTAssertFalse(text.contains(".cursorignore"))
        XCTAssertTrue(text.contains("README.md"))
        XCTAssertTrue(text.contains("Claude Code"))
    }

    func testRefreshesPresentIgnoreFilesWhenPatternsExposed() throws {
        // File is present but patterns still leak → ship a full-coverage replacement
        // so the repo actually passes, not just a README.
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true],
            exposedPatterns: [
                ["id": "env-files", "severity": "required", "category": "secret", "count": 2],
            ]
        )
        let data = try XCTUnwrap(
            FixArchiveBuilder.makeArchive(reportJSON: json, repoURL: "https://github.com/org/repo")
        )
        let text = zipText(data)

        XCTAssertTrue(text.contains(".cursorignore"))
        XCTAssertTrue(text.contains(".env*"))
        XCTAssertTrue(text.contains("Updated ignore files"))
    }

    func testReturnsNilWhenNothingToFix() {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true],
            exposedPatterns: [],
            exposedFiles: 0
        )
        XCTAssertNil(FixArchiveBuilder.makeArchive(reportJSON: json, repoURL: "https://github.com/org/repo"))
        XCTAssertFalse(FixArchiveBuilder.hasFixes(reportJSON: json))
    }

    func testReturnsNilForInvalidJSON() {
        XCTAssertNil(FixArchiveBuilder.makeArchive(reportJSON: "not json", repoURL: "x"))
        XCTAssertFalse(FixArchiveBuilder.hasFixes(reportJSON: "not json"))
    }

    func testHasFixesTrueWhenGatingFileMissing() {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": false],
            exposedPatterns: [],
            exposedFiles: 0
        )
        XCTAssertTrue(FixArchiveBuilder.hasFixes(reportJSON: json))
    }

    // Store-only zip keeps names and file contents as literal bytes, so a
    // lossless byte→char decode lets us assert on the raw archive.
    private func zipText(_ data: Data) -> String {
        String(data.map { Character(UnicodeScalar($0)) })
    }

    private func hasZipSignatures(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { return false }
        let localHeader = bytes.prefix(4) == [0x50, 0x4b, 0x03, 0x04]
        let eocd = bytes.suffix(22).prefix(4) == [0x50, 0x4b, 0x05, 0x06]
        return localHeader && eocd
    }
}
