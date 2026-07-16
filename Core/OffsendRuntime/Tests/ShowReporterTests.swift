import XCTest
@testable import OffsendRuntime

final class ShowReporterTests: XCTestCase {
    private func makeGroup(
        typeID: String = "pem-files",
        typeTitle: String = "PEM keys",
        severity: String = "required",
        remediation: String = "Ignore PEM key files.",
        relativePaths: [String]
    ) -> ShowExposedGroup {
        ShowExposedGroup(
            typeID: typeID,
            typeTitle: typeTitle,
            severity: severity,
            remediation: remediation,
            relativePaths: relativePaths
        )
    }

    private func makeReport(
        directoryPath: String = "/tmp/project",
        groups: [ShowExposedGroup],
        scanIncomplete: Bool = false,
        errors: [String] = []
    ) -> ShowReport {
        let total = Set(groups.flatMap(\.relativePaths)).count
        return ShowReport(
            directoryPath: directoryPath,
            groups: groups,
            totalExposedCount: total,
            scanIncomplete: scanIncomplete,
            errors: errors
        )
    }

    func testTextShowsDirectorySummaryMarkerAndRemediation() {
        let report = makeReport(
            groups: [
                makeGroup(severity: "required", relativePaths: ["server.pem"]),
                makeGroup(
                    typeID: "ssh-files",
                    typeTitle: "SSH material",
                    severity: "recommended",
                    remediation: "Ignore SSH directories and id_rsa files.",
                    relativePaths: ["id_rsa"]
                )
            ]
        )

        let output = ShowReporter().render(report, format: .text)

        XCTAssertTrue(output.contains("Scanned: /tmp/project"))
        XCTAssertTrue(output.contains("2 files would be sent to AI tools (1 required, 1 recommended):"))
        XCTAssertTrue(output.contains("✗ PEM keys [required]"))
        XCTAssertTrue(output.contains("! SSH material [recommended]"))
        XCTAssertTrue(output.contains("    Ignore PEM key files."))
        XCTAssertTrue(output.contains("  - server.pem"))
    }

    func testSingleFileIsNotPluralized() {
        let report = makeReport(groups: [makeGroup(relativePaths: ["server.pem"])])

        let output = ShowReporter().render(report, format: .text)

        XCTAssertTrue(output.contains("1 file would be sent to AI tools"))
        XCTAssertFalse(output.contains("1 files"))
    }

    func testNoExposureMessage() {
        let report = makeReport(groups: [])

        let output = ShowReporter().render(report, format: .text)

        XCTAssertTrue(output.contains("AI boundary OK"))
        XCTAssertTrue(output.contains("no sensitive files are exposed"))
        XCTAssertTrue(output.contains("offsend hook install"))
        XCTAssertTrue(output.contains("check --staged --policy"))
    }

    func testIncompleteScanErrorIsShownAlongsideExposure() {
        let report = makeReport(
            groups: [makeGroup(relativePaths: ["server.pem"])],
            scanIncomplete: true,
            errors: ["Exposure scan stopped after 1000 files (limit: 1000). Results may be incomplete."]
        )

        let output = ShowReporter().render(report, format: .text)

        XCTAssertTrue(output.contains("! Exposure scan stopped after 1000 files"))
        XCTAssertTrue(output.contains("1 file would be sent to AI tools"))
    }

    func testLongGroupIsTruncatedWithHint() {
        let paths = (1...60).map { String(format: "secret-%02d.pem", $0) }
        let report = makeReport(groups: [makeGroup(relativePaths: paths)])

        let output = ShowReporter().render(report, format: .text)

        XCTAssertTrue(output.contains("  - secret-50.pem"))
        XCTAssertFalse(output.contains("  - secret-51.pem"))
        XCTAssertTrue(output.contains("… and 10 more (use --format json for the full list)"))
    }

    func testColorIsAppliedOnlyWhenRequested() {
        let report = makeReport(groups: [makeGroup(severity: "required", relativePaths: ["server.pem"])])

        let plain = ShowReporter().render(report, format: .text, useColor: false)
        let colored = ShowReporter().render(report, format: .text, useColor: true)

        XCTAssertFalse(plain.contains("\u{001B}["))
        XCTAssertTrue(colored.contains("\u{001B}[31m"))
    }

    func testJSONIncludesRemediation() {
        let report = makeReport(groups: [makeGroup(relativePaths: ["server.pem"])])

        let output = ShowReporter().render(report, format: .json)

        XCTAssertTrue(output.contains("\"remediation\""))
        XCTAssertTrue(output.contains("Ignore PEM key files."))
        XCTAssertTrue(output.contains("\"scanIncomplete\""))
        XCTAssertTrue(output.contains("\"mcp\""))
    }

    func testMCPSectionRenderedWhenServersPresent() {
        let report = ShowReport(
            directoryPath: "/tmp/project",
            groups: [],
            totalExposedCount: 0,
            scanIncomplete: false,
            errors: [],
            mcp: ShowMCPSection(
                servers: [
                    ShowMCPServer(
                        name: "filesystem",
                        source: "cursor-project",
                        detail: "npx server-filesystem",
                        highRisk: true
                    ),
                ],
                policyMode: nil,
                gateTargets: []
            )
        )

        let output = ShowReporter().render(report, format: .text)
        XCTAssertTrue(output.contains("AI boundary OK"))
        XCTAssertTrue(output.contains("MCP"))
        XCTAssertTrue(output.contains("filesystem"))
        XCTAssertTrue(output.contains("high-risk"))
        XCTAssertTrue(output.contains("gate: missing"))
    }
}
