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

    func testTextReporterRendersFinding() {
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

        let output = CheckReporter().render(report, format: .text, quiet: false)
        XCTAssertTrue(output.contains("secrets.env:3"))
        XCTAssertTrue(output.contains("[block]"))
    }

    func testQuietStillRendersFileIssues() {
        let report = CheckReport(
            fileFindings: [],
            fileIssues: [FileCheckIssue(relativePath: "broken.pdf", message: "Invalid PDF")],
            failPolicy: .block
        )

        let output = CheckReporter().render(report, format: .text, quiet: true)
        XCTAssertTrue(output.contains("broken.pdf"))
        XCTAssertTrue(output.contains("[skipped]"))
    }
}
