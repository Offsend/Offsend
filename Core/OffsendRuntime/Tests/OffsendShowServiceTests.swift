import WorkspacePolicyCore
import XCTest
@testable import OffsendRuntime

final class OffsendShowServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeService() -> OffsendShowService {
        OffsendShowService(configuration: .default)
    }

    private func write(_ relativePath: String, _ contents: String = "value") throws {
        try contents.write(
            to: root.appendingPathComponent(relativePath),
            atomically: true,
            encoding: .utf8
        )
    }

    func testListsExposedSensitiveFilesGroupedByType() throws {
        try write("secrets.json")
        try write("server.pem")

        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertTrue(report.hasExposure)
        XCTAssertEqual(report.totalExposedCount, 2)

        let pemGroup = report.groups.first { $0.typeID == "pem-files" }
        let secretsGroup = report.groups.first { $0.typeID == "secrets-json" }
        XCTAssertEqual(pemGroup?.relativePaths, ["server.pem"])
        XCTAssertEqual(secretsGroup?.relativePaths, ["secrets.json"])
    }

    func testNoExposureWhenIgnoreFilesCoverSensitiveFiles() throws {
        try write("secrets.json")
        // `prepare` creates the full set of ignore files whose template covers secrets.json.
        _ = OffsendPrepareService(configuration: .default).run(directoryURL: root)

        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertFalse(report.hasExposure)
        XCTAssertTrue(report.groups.isEmpty)
    }

    func testEmptyDirectoryHasNoExposure() throws {
        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertFalse(report.hasExposure)
        XCTAssertTrue(report.groups.isEmpty)
    }

    func testReportsErrorForUnavailableDirectory() {
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        let report = makeService().run(directoryURL: missing)

        XCTAssertTrue(report.hasErrors)
        XCTAssertFalse(report.hasExposure)
        XCTAssertTrue(report.groups.isEmpty)
    }

    func testManagedIgnoreDriftIsWarningNotError() throws {
        try write(
            ".offsend.yml",
            """
            version: 1
            ignore:
              commit: true
              patterns:
                - "team-secret/"
            """
        )
        // Existing ignore file without the managed pattern → drift.
        try write(".cursorignore", "personal/\n")

        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.errors.isEmpty, "drift must not fail `offsend show`")
        XCTAssertTrue(report.warnings.contains { $0.contains("team-secret/") && $0.contains("offsend ignore --sync") })
    }

    func testRequiredSeverityGroupsSortFirst() throws {
        try write("secrets.json")
        try write(".env")

        let report = makeService().run(directoryURL: root)

        let severities = report.groups.map(\.severity)
        let ranks = severities.map { $0 == AIWorkspacePrivacyRuleSeverity.required.rawValue ? 0 : 1 }
        XCTAssertEqual(ranks, ranks.sorted(), "Required-severity groups must come before recommended ones.")
    }
}
