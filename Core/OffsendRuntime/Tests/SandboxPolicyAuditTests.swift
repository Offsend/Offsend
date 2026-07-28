import XCTest
@testable import OffsendRuntime

final class SandboxPolicyAuditTests: XCTestCase {
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("offsend-sandbox-audit-\(UUID().uuidString)")
        root = base.appendingPathComponent("repo")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func policy(enabled: Bool?) -> OffsendProjectConfig {
        OffsendProjectConfig(sandbox: OffsendProjectSandboxConfig(enabled: enabled))
    }

    private func write(_ json: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: url)
    }

    private func findings(
        enabled: Bool?,
        targets: [AIEditorHookTarget],
        nonoAvailable: Bool = false
    ) -> [SandboxPolicyAudit.Finding] {
        SandboxPolicyAudit.findings(
            repositoryURL: root,
            config: policy(enabled: enabled),
            targets: targets,
            nonoAvailable: nonoAvailable,
            homeDirectory: home
        )
    }

    private func sync(targets: [AIEditorHookTarget], nonoAvailable: Bool = false) {
        _ = SandboxSyncService().run(
            repositoryURL: root,
            config: policy(enabled: true),
            targets: targets,
            nonoAvailable: nonoAvailable
        )
    }

    func testNoDeclarationMeansNothingToVerify() throws {
        try write(#"{"type":"insecure_none"}"#, to: ".cursor/sandbox.json")

        XCTAssertTrue(findings(enabled: nil, targets: [.cursor]).isEmpty)
    }

    func testGeneratedConfigsPassCleanly() {
        sync(targets: [.cursor, .claude])

        XCTAssertTrue(findings(enabled: true, targets: [.cursor, .claude]).isEmpty)
    }

    func testMissingConfigIsReportedAsDrift() {
        let result = findings(enabled: true, targets: [.cursor])

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isFailure)
        XCTAssertTrue(result[0].message.contains(".cursor/sandbox.json"))
        XCTAssertTrue(result[0].message.contains("offsend sync"))
    }

    func testCursorInsecureNoneFails() throws {
        sync(targets: [.cursor])
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appendingPathComponent(".cursor/sandbox.json"))
            ) as? [String: Any]
        )
        object["type"] = "insecure_none"
        try Data(
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        ).write(to: root.appendingPathComponent(".cursor/sandbox.json"))

        let result = findings(enabled: true, targets: [.cursor])

        XCTAssertTrue(result.contains { $0.isFailure && $0.message.contains("insecure_none") })
    }

    func testClaudeEscapeHatchAndDisabledFilesystemFail() throws {
        try write(
            #"""
            {"sandbox":{"enabled":true,"allowUnsandboxedCommands":true,
             "filesystem":{"disabled":true,"denyRead":[]},"network":{"allowedDomains":[]}}}
            """#,
            to: ".claude/settings.json"
        )

        let result = findings(enabled: true, targets: [.claude])

        XCTAssertTrue(result.contains { $0.isFailure && $0.message.contains("allowUnsandboxedCommands") })
        XCTAssertTrue(result.contains { $0.isFailure && $0.message.contains("filesystem.disabled") })
    }

    func testClaudeSandboxTurnedOffFails() throws {
        try write(#"{"sandbox":{"enabled":false}}"#, to: ".claude/settings.json")

        let result = findings(enabled: true, targets: [.claude])

        XCTAssertTrue(result.contains { $0.isFailure && $0.message.contains("sandbox.enabled is not true") })
    }

    func testClaudeSandboxOffIsExpectedWhenNonoOwnsFilesystem() {
        sync(targets: [.claude], nonoAvailable: true)

        let result = findings(enabled: true, targets: [.claude], nonoAvailable: true)

        XCTAssertTrue(result.isEmpty, "\(result)")
    }

    func testCodexDangerFullAccessFails() throws {
        let codex = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try Data(#"sandbox_mode = "danger-full-access""#.utf8)
            .write(to: codex.appendingPathComponent("config.toml"))

        let result = findings(enabled: true, targets: [.codex])

        XCTAssertTrue(result.contains { $0.isFailure && $0.message.contains("danger-full-access") })
    }

    func testCodexWithoutUserConfigOnlyWarns() {
        let result = findings(enabled: true, targets: [.codex])

        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isFailure)
        XCTAssertTrue(result[0].message.contains("~/.codex/config.toml"))
    }

    func testWindsurfWarnsWithoutFailing() {
        let result = findings(enabled: true, targets: [.windsurf])

        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isFailure)
        XCTAssertTrue(result[0].message.contains("no sandbox"))
    }

    func testDoctorPrintsMechanismAndReachedPosition() {
        let report = SandboxSyncService().run(
            repositoryURL: root,
            config: OffsendProjectConfig(
                ignore: OffsendProjectIgnoreConfig(patterns: ["*.pem"]),
                sandbox: OffsendProjectSandboxConfig(enabled: true)
            ),
            targets: [.cursor],
            nonoAvailable: false,
            dryRun: true
        )

        let checks = OffsendDoctor.sandboxChecks(report: report, audit: [])

        let mechanism = try? XCTUnwrap(checks.first { $0.name == "sandbox-cursor" })
        XCTAssertEqual(mechanism?.status, .ok)
        XCTAssertTrue(mechanism?.message.contains("cursorNative") == true)
        XCTAssertTrue(mechanism?.message.contains("no read-deny") == true)
        XCTAssertTrue(checks.contains { $0.name == "sandbox-coverage" && $0.message.contains("*.pem") })
    }

    func testDoctorFailsOnWeakeningFinding() {
        let checks = OffsendDoctor.sandboxChecks(
            report: SandboxSyncService.Report(enabled: true),
            audit: [SandboxPolicyAudit.Finding(message: "weakened", isFailure: true)]
        )

        XCTAssertEqual(checks.first { $0.name == "sandbox-policy" }?.status, .fail)
    }
}
