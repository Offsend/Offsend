import XCTest
@testable import OffsendRuntime

final class OffsendDoctorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeConfig(_ contents: String) throws {
        try contents.write(
            to: root.appendingPathComponent(".offsend.yml"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - needsIgnoreMaterialization (fresh-clone detection)

    func testNeedsMaterializationWhenConfigExistsButIgnoreFilesMissing() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              patterns:
                - "secrets/"
            """
        )

        XCTAssertTrue(
            OffsendDoctor.needsIgnoreMaterialization(
                configLoader: ProjectConfigLoader(),
                directory: root
            )
        )
    }

    func testNoMaterializationNeededAfterSync() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              patterns:
                - "secrets/"
            """
        )

        let report = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))

        XCTAssertFalse(
            OffsendDoctor.needsIgnoreMaterialization(
                configLoader: ProjectConfigLoader(),
                directory: root
            )
        )
    }

    func testNoMaterializationNeededWithoutConfig() {
        XCTAssertFalse(
            OffsendDoctor.needsIgnoreMaterialization(
                configLoader: ProjectConfigLoader(),
                directory: root
            )
        )
    }

    func testNarrowedToolsOnlyCheckConfiguredIgnoreFiles() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              tools: [cursor]
              patterns:
                - "secrets/"
            """
        )

        let report = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))

        // Only cursor files were materialized; the narrowed tool list must not
        // report missing files for other editors (false positives).
        XCTAssertFalse(
            OffsendDoctor.needsIgnoreMaterialization(
                configLoader: ProjectConfigLoader(),
                directory: root
            )
        )
    }

    // MARK: - Next-actions tip

    func testNextActionsTipSuggestsSyncWhenConfigPresent() {
        let report = DoctorReport(
            checks: [
                DoctorCheck(name: "project-config", status: .ok, message: "/repo/.offsend.yml"),
                DoctorCheck(
                    name: "next-actions",
                    status: .warn,
                    message: "1. offsend sync   # after clone: materialize ignore files + hooks from .offsend.yml"
                ),
            ],
            suggestedActions: [
                "offsend sync   # after clone: materialize ignore files + hooks from .offsend.yml"
            ]
        )

        let text = DoctorReporter().render(report, format: .text)
        XCTAssertTrue(text.contains("Tip: offsend sync"), text)
        XCTAssertFalse(text.contains("offsend setup"), text)
    }

    func testNextActionsTipSuggestsInitWithoutConfig() {
        let report = DoctorReport(
            checks: [
                DoctorCheck(
                    name: "project-config",
                    status: .warn,
                    message: "No \(ProjectConfigLoader.filename) found for the current directory."
                ),
                DoctorCheck(
                    name: "next-actions",
                    status: .warn,
                    message: "1. offsend init --template <stack>   # create shared .offsend.yml (commit it for the team)"
                ),
            ],
            suggestedActions: [
                "offsend init --template <stack>   # create shared .offsend.yml (commit it for the team)"
            ]
        )

        let text = DoctorReporter().render(report, format: .text)
        XCTAssertTrue(text.contains("Tip: offsend init"), text)
        XCTAssertFalse(text.contains("offsend setup"), text)
    }

    // MARK: - hasManagedIgnoreDrift

    func testHasManagedIgnoreDriftWhenPatternsMissingFromIgnoreFile() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns:
                - "team-secret/"
            """
        )
        try "personal/\n".write(
            to: root.appendingPathComponent(".cursorignore"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertTrue(
            OffsendDoctor.hasManagedIgnoreDrift(
                configLoader: ProjectConfigLoader(),
                directory: root
            )
        )
    }

    func testNoManagedIgnoreDriftAfterSync() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              patterns:
                - "team-secret/"
            """
        )
        let report = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))

        XCTAssertFalse(
            OffsendDoctor.hasManagedIgnoreDrift(
                configLoader: ProjectConfigLoader(),
                directory: root
            )
        )
    }
}
