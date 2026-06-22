import WorkspacePolicyCore
import XCTest
@testable import OffsendRuntime

final class OffsendReportServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeService() -> OffsendReportService {
        OffsendReportService(configuration: .default)
    }

    private func write(_ relativePath: String, _ contents: String = "value") throws {
        try contents.write(
            to: root.appendingPathComponent(relativePath),
            atomically: true,
            encoding: .utf8
        )
    }

    func testAggregatesExposedPatternsAsCountsWithoutPaths() throws {
        try write("secrets.json")
        try write("server.pem")

        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.errorIDs.isEmpty)
        XCTAssertTrue(report.scanComplete)
        XCTAssertEqual(report.totalExposedFiles, 2)

        let pem = report.exposedPatterns.first { $0.patternID == "pem-files" }
        let secrets = report.exposedPatterns.first { $0.patternID == "secrets-json" }
        XCTAssertEqual(pem?.count, 1)
        XCTAssertEqual(secrets?.count, 1)
    }

    func testDetectsPIIAndHistoryPatternsWithCategory() throws {
        try write("app.sqlite")
        try write("debug.log")
        try write(".bash_history")

        let report = makeService().run(directoryURL: root)

        let db = report.exposedPatterns.first { $0.patternID == "local-databases" }
        let log = report.exposedPatterns.first { $0.patternID == "log-files" }
        let history = report.exposedPatterns.first { $0.patternID == "shell-history" }
        XCTAssertEqual(db?.category, "pii")
        XCTAssertEqual(log?.category, "pii")
        XCTAssertEqual(history?.category, "history")
    }

    func testNewPatternsAreCoveredByPrepareTemplate() throws {
        try write("app.sqlite")
        try write("debug.log")
        try write(".git-credentials")
        try write("signing.keystore")
        _ = OffsendPrepareService(configuration: .default).run(directoryURL: root)

        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.errorIDs.isEmpty)
        XCTAssertTrue(
            report.exposedPatterns.isEmpty,
            "prepare's template must cover the new patterns; still exposed: \(report.exposedPatterns.map(\.patternID))"
        )
    }

    func testReportsIgnoreFilePresence() throws {
        try write(".gitignore", "*.log\n")

        let report = makeService().run(directoryURL: root)

        let git = report.ignoreFiles.first { $0.ruleID == "git-ignore" }
        let cursor = report.ignoreFiles.first { $0.ruleID == "cursor-ignore" }
        XCTAssertEqual(git?.present, true)
        XCTAssertEqual(cursor?.present, false)
    }

    func testNoExposureWhenIgnoreFilesCoverSensitiveFiles() throws {
        try write("secrets.json")
        _ = OffsendPrepareService(configuration: .default).run(directoryURL: root)

        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.errorIDs.isEmpty)
        XCTAssertTrue(report.exposedPatterns.isEmpty)
        XCTAssertEqual(report.totalExposedFiles, 0)
    }

    func testUnavailableDirectoryIsMarkedIncompleteWithErrorIDOnly() {
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)

        let report = makeService().run(directoryURL: missing)

        XCTAssertFalse(report.scanComplete)
        XCTAssertFalse(report.errorIDs.isEmpty)
        XCTAssertTrue(report.exposedPatterns.isEmpty)
        for errorID in report.errorIDs {
            XCTAssertFalse(errorID.contains("/"), "Error identifiers must not leak paths.")
        }
    }

    func testRulesetVersionIsStableAndSetDependent() {
        let report = makeService().run(directoryURL: root)
        let again = makeService().run(directoryURL: root)
        XCTAssertEqual(report.rulesetVersion, again.rulesetVersion)
        XCTAssertFalse(report.rulesetVersion.isEmpty)

        let reduced = AIWorkspacePrivacyAuditConfiguration(
            rules: AIWorkspacePrivacyRule.defaultRules,
            sensitivePatterns: Array(AIWorkspaceSensitivePattern.defaultPatterns.prefix(1))
        )
        let reducedReport = OffsendReportService(configuration: reduced).run(directoryURL: root)
        XCTAssertNotEqual(report.rulesetVersion, reducedReport.rulesetVersion)
    }

    func testReportContainsNoFileNames() throws {
        try write("secrets.json")
        try write("server.pem")

        let report = makeService().run(directoryURL: root)
        let json = ReportReporter().renderJSON(report, toolVersion: "1.2.3", generatedAt: Date())

        XCTAssertFalse(json.contains("secrets.json"))
        XCTAssertFalse(json.contains("server.pem"))
        XCTAssertFalse(json.contains(root.path))
    }
}
