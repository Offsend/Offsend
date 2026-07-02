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
        XCTAssertTrue(html.contains("noindex, nofollow"))
        XCTAssertTrue(html.contains("env-files"))
        XCTAssertTrue(html.contains(".cursorignore"))
        XCTAssertTrue(html.contains("Privacy score"))
        XCTAssertTrue(html.contains("How to fix"))
    }

    func testRendersPrivacyScore() throws {
        // cursor-ignore present (required, no penalty), claude-ignore missing (recommended
        // gating rule, -3), one required-severity exposed pattern (-25). 100 - 3 - 25 = 72.
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true, "claude-ignore": false]
        )
        let html = try render(json: json)
        XCTAssertTrue(html.contains("72/100"))
    }

    func testScorePenalizesExposedSecretsRegardlessOfIgnoreFiles() throws {
        // Even with every gating ignore file present, a required-severity exposed secret
        // must still cost real points — the score can't be "checkbox-only".
        let allPresent = Dictionary(
            uniqueKeysWithValues: ["cursor-ignore", "claude-ignore", "copilot-exclude"].map { ($0, true) }
        )
        let json = TestSupport.sampleReportJSON(ignoreFiles: allPresent)
        let html = try render(json: json)
        XCTAssertTrue(html.contains("75/100"), "expected 100 - 25 (required exposed pattern) = 75")
    }

    func testScoreIs100WhenNoIssues() throws {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true],
            exposedPatterns: [],
            exposedFiles: 0
        )
        let html = try render(json: json)
        XCTAssertTrue(html.contains("100/100"))
        XCTAssertTrue(html.contains("No privacy issues found"))
    }

    func testShowsFixItButtonWithEmbeddedFilesWhenFixesExist() throws {
        let json = TestSupport.sampleReportJSON(ignoreFiles: ["cursor-ignore": false])
        let html = try render(json: json)
        XCTAssertTrue(html.contains("Fix it"))
        XCTAssertTrue(html.contains("id=\"fix-open\""))
        // The command modal builds itself from the fix files embedded in the page.
        XCTAssertTrue(html.contains("id=\"fix-files-data\""))
        XCTAssertTrue(html.contains(".cursorignore"))
    }

    func testHidesFixItButtonWhenNoFixes() throws {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true],
            exposedPatterns: [],
            exposedFiles: 0
        )
        let html = try render(json: json)
        XCTAssertFalse(html.contains("id=\"fix-open\""))
        XCTAssertFalse(html.contains("id=\"fix-files-data\""))
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

    func testSplitsGatingAndContextIgnoreFiles() throws {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": true, "git-ignore": true]
        )
        let html = try render(json: json)
        XCTAssertTrue(html.contains("AI ignore"))
        XCTAssertTrue(html.contains("exclude files"))
        XCTAssertTrue(html.contains("Other AI context files"))
        XCTAssertTrue(html.contains(".cursorignore"))
        XCTAssertTrue(html.contains(".gitignore"))
    }

    func testHowToFixSurfacesRemediationText() throws {
        let json = TestSupport.sampleReportJSON(
            ignoreFiles: ["cursor-ignore": false],
            exposedPatterns: [
                ["id": "env-files", "severity": "required", "category": "secret", "count": 2],
            ]
        )
        let html = try render(json: json)
        XCTAssertTrue(html.contains("Environment files exposed"))
        XCTAssertTrue(html.contains("Ignore .env and .env.* files."))
        XCTAssertTrue(html.contains("Add .cursorignore for Cursor"))
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
