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

    // MARK: - Cursor minimum version

    func testCursorVersionCheckAcceptsVersionThreeOrNewer() {
        XCTAssertEqual(OffsendDoctor.cursorVersionCheck(version: "3.0.0").status, .ok)
        XCTAssertEqual(OffsendDoctor.cursorVersionCheck(version: "4.1.2").status, .ok)
    }

    func testCursorVersionCheckWarnsForPreThreeVersion() {
        let check = OffsendDoctor.cursorVersionCheck(version: "2.10.4")

        XCTAssertEqual(check.name, "cursor-version")
        XCTAssertEqual(check.status, .warn)
        XCTAssertTrue(check.message.contains("CVE-2026-48124"))
    }

    func testCursorVersionCheckWarnsWhenVersionCannotBeParsed() {
        XCTAssertEqual(OffsendDoctor.cursorVersionCheck(version: "unknown").status, .warn)
    }

    func testProvenanceLedgerCheckWarnsForExecutableTrustSurfaceChanges() {
        let entry = ArtifactProvenanceEntry(
            timestamp: Date(),
            repositoryID: "repository",
            relativePath: ".cursor/hooks.json",
            pathHash: "path",
            artifactKind: .editorHookConfig,
            adapter: "cursor",
            toolName: "afterFileEdit",
            outcome: "changed",
            contentHash: "content"
        )

        let check = OffsendDoctor.provenanceLedgerCheck(directory: root, entries: [entry])

        XCTAssertEqual(check.name, "artifact-provenance")
        XCTAssertEqual(check.status, .warn)
        XCTAssertTrue(check.message.contains(".cursor/hooks.json"))
    }

    func testProvenanceLedgerCheckKeepsObserveOnlyChangesInformational() {
        let entry = ArtifactProvenanceEntry(
            timestamp: Date(),
            repositoryID: "repository",
            relativePath: ".venv/bin/python",
            pathHash: "path",
            artifactKind: .virtualEnvironmentInterpreter,
            adapter: "claude",
            toolName: "Write",
            outcome: "changed",
            contentHash: nil
        )

        XCTAssertEqual(
            OffsendDoctor.provenanceLedgerCheck(directory: root, entries: [entry]).status,
            .ok
        )
    }

    func testProvenanceLedgerCheckReportsBrokenChainAheadOfEntries() {
        let check = OffsendDoctor.provenanceLedgerCheck(
            directory: root,
            entries: [],
            chain: .broken(line: 4)
        )

        XCTAssertEqual(check.status, .warn)
        XCTAssertTrue(check.message.contains("entry 4"))
        XCTAssertTrue(check.message.contains("modified after the fact"))
    }

    func testProvenanceLedgerCheckReportsTruncatedLogAheadOfEntries() {
        let check = OffsendDoctor.provenanceLedgerCheck(
            directory: root,
            entries: [],
            chain: .truncated(expected: 12, found: 9)
        )

        XCTAssertEqual(check.status, .warn)
        XCTAssertTrue(check.message.contains("12 were recorded, 9 remain"))
        XCTAssertTrue(check.message.contains("shortened the log"))
    }

    func testPrivilegedDaemonCheckWarnsWithoutHealthyShellGate() {
        let check = OffsendDoctor.privilegedDaemonCheck(
            endpointLabels: ["docker-desktop"],
            shellGateActive: false
        )

        XCTAssertEqual(check.name, "privileged-daemons")
        XCTAssertEqual(check.status, .warn)
        XCTAssertTrue(check.message.contains("host-side container execution"))
    }

    func testPrivilegedDaemonCheckReportsCoverageAndResidualGap() {
        let check = OffsendDoctor.privilegedDaemonCheck(
            endpointLabels: ["containerd", "docker-system", "docker-system"],
            shellGateActive: true
        )

        XCTAssertEqual(check.status, .ok)
        XCTAssertTrue(check.message.contains("containerd, docker-system"))
        XCTAssertTrue(check.message.contains("custom clients remain residual gaps"))
    }

    func testEnvironmentInvocationCheckReflectsShellGateHealth() {
        let active = OffsendDoctor.environmentInvocationCheck(shellGateActive: true)
        XCTAssertEqual(active.name, "environment-invocation-gate")
        XCTAssertEqual(active.status, .ok)
        XCTAssertTrue(active.message.contains("already-poisoned parent environments"))

        let inactive = OffsendDoctor.environmentInvocationCheck(shellGateActive: false)
        XCTAssertEqual(inactive.status, .warn)
        XCTAssertTrue(inactive.message.contains("shell-gate"))
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

    func testNextActionsTipSuggestsHistoryAuditWhenFirstAction() {
        let report = DoctorReport(
            checks: [
                DoctorCheck(name: "project-config", status: .ok, message: "/repo/.offsend.yml"),
                DoctorCheck(
                    name: "next-actions",
                    status: .warn,
                    message: "1. offsend history audit   # 2 local transcript(s) may already hold secrets"
                ),
            ],
            suggestedActions: [
                "offsend history audit   # 2 local transcript(s) may already hold secrets"
            ]
        )

        let text = DoctorReporter().render(report, format: .text)
        XCTAssertTrue(text.contains("Tip: offsend history audit"), text)
        XCTAssertTrue(text.contains("scrub --apply"), text)
        XCTAssertFalse(text.contains("Tip: offsend sync"), text)
    }

    func testNextActionsTipSuggestsHistoryScrubWhenFirstAction() {
        let report = DoctorReport(
            checks: [
                DoctorCheck(name: "project-config", status: .ok, message: "/repo/.offsend.yml"),
                DoctorCheck(
                    name: "next-actions",
                    status: .warn,
                    message: "1. offsend history scrub --apply   # 1/2 transcript(s) already hold secrets"
                ),
            ],
            suggestedActions: [
                "offsend history scrub --apply   # 1/2 transcript(s) already hold secrets"
            ]
        )

        let text = DoctorReporter().render(report, format: .text)
        XCTAssertTrue(text.contains("Tip: offsend history scrub --apply"), text)
        XCTAssertFalse(text.contains("Tip: offsend history audit"), text)
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
