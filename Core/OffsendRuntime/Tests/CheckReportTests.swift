import DetectionCore
import XCTest
@testable import OffsendRuntime

final class CheckReportTests: XCTestCase {
    func testShouldFailOnBlockWhenCriticalSecretPresent() {
        let report = CheckReport(
            fileFindings: [
                FileCheckFinding(
                    relativePath: "config.swift",
                    line: 1,
                    entityType: .awsAccessKeyId,
                    recommendedAction: .block,
                    hasCriticalSecret: true
                )
            ],
            failPolicy: .block
        )
        XCTAssertTrue(report.shouldFail)
        XCTAssertEqual(report.blockingCount, 1)
    }

    func testShouldNotFailWhenPolicyIsNone() {
        let report = CheckReport(
            fileFindings: [
                FileCheckFinding(
                    relativePath: "config.swift",
                    line: 1,
                    entityType: .email,
                    recommendedAction: .warn,
                    hasCriticalSecret: false
                )
            ],
            failPolicy: .none
        )
        XCTAssertFalse(report.shouldFail)
    }

    func testDigestGroupsFindingsByFileAndOmitsLineDetail() {
        let report = CheckReport(
            fileFindings: [
                FileCheckFinding(
                    relativePath: "secrets.env",
                    line: 3,
                    entityType: .apiKeyGeneric,
                    recommendedAction: .block,
                    hasCriticalSecret: true
                ),
                FileCheckFinding(
                    relativePath: "secrets.env",
                    line: 7,
                    entityType: .awsAccessKeyId,
                    recommendedAction: .warn,
                    hasCriticalSecret: false
                )
            ],
            failPolicy: .block
        )

        let output = CheckReporter().render(report, format: .text, quiet: false)
        XCTAssertTrue(output.contains("✗ secrets.env  1 blocking, 1 warning"))
        XCTAssertFalse(output.contains("secrets.env:3"), "Digest should not print per-line detail.")
        XCTAssertFalse(output.contains("[block]"))
        XCTAssertTrue(output.contains("1 blocking, 1 warning(s) across 1 file. Check failed."))
    }

    func testVerboseListsEveryFindingWithLineDetail() {
        let report = CheckReport(
            fileFindings: [
                FileCheckFinding(
                    relativePath: "secrets.env",
                    line: 3,
                    entityType: .apiKeyGeneric,
                    recommendedAction: .block,
                    hasCriticalSecret: true
                )
            ],
            failPolicy: .block
        )

        let output = CheckReporter().render(report, format: .text, quiet: false, verbose: true)
        XCTAssertTrue(output.contains("secrets.env:3"))
        XCTAssertTrue(output.contains("[block]"))
    }

    func testDigestTruncatesLongFileList() {
        let findings = (1...15).map { index in
            FileCheckFinding(
                relativePath: String(format: "file-%02d.txt", index),
                line: 1,
                entityType: .email,
                recommendedAction: .warn,
                hasCriticalSecret: false
            )
        }
        let report = CheckReport(fileFindings: findings, failPolicy: .warn)

        let output = CheckReporter().render(report, format: .text, quiet: false)
        XCTAssertTrue(output.contains("… and 5 more files (use --verbose)"))
    }

    func testColorIsAppliedOnlyWhenRequested() {
        let report = CheckReport(
            fileFindings: [
                FileCheckFinding(
                    relativePath: "secrets.env",
                    line: 3,
                    entityType: .apiKeyGeneric,
                    recommendedAction: .block,
                    hasCriticalSecret: true
                ),
                FileCheckFinding(
                    relativePath: "notes.txt",
                    line: 1,
                    entityType: .email,
                    recommendedAction: .warn,
                    hasCriticalSecret: false
                )
            ],
            failPolicy: .block
        )

        let plain = CheckReporter().render(report, format: .text, quiet: false, useColor: false)
        let colored = CheckReporter().render(report, format: .text, quiet: false, useColor: true)

        XCTAssertFalse(plain.contains("\u{001B}["))
        XCTAssertTrue(colored.contains("\u{001B}[31m"), "Blocking findings should be red.")
        XCTAssertTrue(colored.contains("\u{001B}[33m"), "Warning findings should be yellow.")
    }

    func testSkippedFilesCollapseToCountByDefault() {
        let report = CheckReport(
            fileFindings: [],
            fileIssues: [
                FileCheckIssue(relativePath: "broken.pdf", message: "Invalid PDF"),
                FileCheckIssue(relativePath: "broken2.pdf", message: "Invalid PDF")
            ],
            failPolicy: .block
        )

        let quiet = CheckReporter().render(report, format: .text, quiet: true)
        XCTAssertTrue(quiet.contains("2 files skipped (use --verbose to list)"))
        XCTAssertFalse(quiet.contains("broken.pdf"))

        let verbose = CheckReporter().render(report, format: .text, quiet: true, verbose: true)
        XCTAssertTrue(verbose.contains("broken.pdf"))
        XCTAssertTrue(verbose.contains("[skipped]"))
    }

    func testQuietOmitsSummaryFooter() {
        let report = CheckReport(
            fileFindings: [
                FileCheckFinding(
                    relativePath: "secrets.env",
                    line: 3,
                    entityType: .apiKeyGeneric,
                    recommendedAction: .block,
                    hasCriticalSecret: true
                )
            ],
            failPolicy: .block
        )

        let output = CheckReporter().render(report, format: .text, quiet: true)
        XCTAssertTrue(output.contains("✗ secrets.env  1 blocking"))
        XCTAssertFalse(output.contains("Check failed."))
    }
}
