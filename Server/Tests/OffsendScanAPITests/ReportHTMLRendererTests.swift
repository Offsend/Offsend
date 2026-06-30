import XCTest
@testable import OffsendScanAPI

final class ReportHTMLRendererTests: XCTestCase {
    private var templates: HTMLTemplateRenderer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        templates = try HTMLTemplateRenderer.load()
    }

    func testRendersHTMLFromReportJSON() throws {
        let json = TestSupport.sampleReportJSON()
        let html = try render(json: json)
        XCTAssertTrue(html.contains("env-files"))
        XCTAssertTrue(html.contains("cursor-ignore"))
        XCTAssertTrue(html.contains("Privacy score"))
    }

    func testRendersPrivacyScore() throws {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true, "claude-ignore": false],
            exposedFiles: 2
        )
        let html = try render(json: json)
        // ignoreRatio=0.5 -> 35, exposure penalty=2 -> ~29.4, total ~64
        XCTAssertTrue(html.contains("64/100"))
    }

    func testRendersQuestionMarkScoreForInvalidJSON() throws {
        let html = try render(json: "not json")
        XCTAssertTrue(html.contains("<div class=\"score\">?</div>"))
        XCTAssertTrue(html.contains("No data"))
    }

    func testRendersNoPatternsRowWhenEmpty() throws {
        let json = TestSupport.sampleReportJSON(exposedPatterns: [], exposedFiles: 0)
        let html = try render(json: json)
        XCTAssertTrue(html.contains("No exposed sensitive pattern types detected."))
    }

    func testRendersIncompleteScanWarning() throws {
        let json = TestSupport.sampleReportJSON(scanComplete: false)
        let html = try render(json: json)
        XCTAssertTrue(html.contains("Scan incomplete"))
    }

    func testRendersCompletedScanMessage() throws {
        let json = TestSupport.sampleReportJSON(scanComplete: true)
        let html = try render(json: json)
        XCTAssertTrue(html.contains("Scan completed."))
    }

    func testRendersErrorsSection() throws {
        let json = TestSupport.sampleReportJSON(errors: ["scan-timeout", "partial-read"])
        let html = try render(json: json)
        XCTAssertTrue(html.contains("<h2>Errors</h2>"))
        XCTAssertTrue(html.contains("scan-timeout"))
        XCTAssertTrue(html.contains("partial-read"))
    }

    func testOmitsErrorsSectionWhenEmpty() throws {
        let json = TestSupport.sampleReportJSON(errors: [])
        let html = try render(json: json)
        XCTAssertFalse(html.contains("<h2>Errors</h2>"))
    }

    func testEscapesHTMLInUserControlledValues() throws {
        let json = TestSupport.sampleReportJSON()
        let html = try ReportHTMLRenderer.render(
            templates: templates,
            jobID: "job-<script>",
            repoURL: "https://github.com/org/repo\"><script>alert(1)</script>",
            reportJSON: json,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("&quot;"))
    }

    func testRendersIgnoreFilePresenceLabels() throws {
        let json = TestSupport.sampleReportJSON(ignoreFiles: ["cursor-ignore": true, "claude-ignore": false])
        let html = try render(json: json)
        XCTAssertTrue(html.contains(">yes<"))
        XCTAssertTrue(html.contains(">missing<"))
        XCTAssertTrue(html.contains("class=\"ok\""))
        XCTAssertTrue(html.contains("class=\"bad\""))
    }

    func testIncludesJobAndRepositoryMetadata() throws {
        let html = try ReportHTMLRenderer.render(
            templates: templates,
            jobID: "job-abc",
            repoURL: "https://github.com/offsend/macos",
            reportJSON: TestSupport.sampleReportJSON(),
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(html.contains("job-abc"))
        XCTAssertTrue(html.contains("https://github.com/offsend/macos"))
        XCTAssertTrue(html.contains("Offsend AI Privacy Report"))
    }

    private func render(json: String) throws -> String {
        try ReportHTMLRenderer.render(
            templates: templates,
            jobID: "job-1",
            repoURL: "https://github.com/offsend/macos",
            reportJSON: json,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
