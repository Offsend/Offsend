import XCTest
@testable import OffsendRuntime

final class SandboxSyncServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("offsend-sandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func config(
        enabled: Bool?,
        networkDefault: String? = nil,
        allow: [String]? = nil,
        patterns: [String]? = nil
    ) -> OffsendProjectConfig {
        OffsendProjectConfig(
            ignore: patterns == nil ? nil : OffsendProjectIgnoreConfig(patterns: patterns),
            sandbox: OffsendProjectSandboxConfig(
                enabled: enabled,
                network: networkDefault == nil && allow == nil
                    ? nil
                    : OffsendProjectSandboxNetworkConfig(default: networkDefault, allow: allow)
            )
        )
    }

    private func json(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDisabledPolicyWritesNothing() throws {
        let report = SandboxSyncService().run(
            repositoryURL: root,
            config: config(enabled: nil),
            targets: [.cursor, .claude],
            nonoAvailable: false
        )

        XCTAssertFalse(report.enabled)
        XCTAssertTrue(report.changes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursor/sandbox.json").path))
    }

    func testCursorGetsEgressOnlyBecauseItHasNoReadDeny() throws {
        let report = SandboxSyncService().run(
            repositoryURL: root,
            config: config(enabled: true, allow: ["api.internal"], patterns: ["secrets", "*.pem"]),
            targets: [.cursor],
            nonoAvailable: false
        )

        XCTAssertEqual(report.plans.first?.mechanism, .cursorNative)
        XCTAssertEqual(report.plans.first?.guarantee.readDeniable, false)

        let sandbox = try json(".cursor/sandbox.json")
        let network = try XCTUnwrap(sandbox["networkPolicy"] as? [String: Any])
        XCTAssertEqual(network["default"] as? String, "deny")
        XCTAssertEqual(network["allow"] as? [String], ["api.internal"])
        XCTAssertNotEqual(sandbox["type"] as? String, "insecure_none")
        // Cursor cannot deny reads, so no path list is invented for it.
        XCTAssertNil(sandbox["filesystem"])
    }

    func testClaudeNativeDeniesReadsAndClosesTheEscapeHatch() throws {
        _ = SandboxSyncService().run(
            repositoryURL: root,
            config: config(enabled: true, patterns: ["secrets/prod", "*.pem", ".env*"]),
            targets: [.claude],
            nonoAvailable: false
        )

        let settings = try json(".claude/settings.json")
        let sandbox = try XCTUnwrap(settings["sandbox"] as? [String: Any])
        XCTAssertEqual(sandbox["enabled"] as? Bool, true)
        XCTAssertEqual(sandbox["allowUnsandboxedCommands"] as? Bool, false)
        let filesystem = try XCTUnwrap(sandbox["filesystem"] as? [String: Any])
        // Only path-shaped patterns; globs would go stale the moment a new file
        // matches, so they are reported instead of expanded.
        XCTAssertEqual(filesystem["denyRead"] as? [String], ["secrets/prod"])
        XCTAssertNil(filesystem["disabled"])
        let network = try XCTUnwrap(sandbox["network"] as? [String: Any])
        XCTAssertEqual(network["allowedDomains"] as? [String], [])
    }

    func testGlobPatternsAreReportedAsUncovered() {
        let report = SandboxSyncService().run(
            repositoryURL: root,
            config: config(enabled: true, patterns: ["secrets/prod", "*.pem", ".env*"]),
            targets: [.claude],
            nonoAvailable: false
        )

        XCTAssertEqual(report.uncoveredPatterns, ["*.pem", ".env*"])
    }

    func testNonoOwnsFilesystemAndClaudeSandboxIsSwitchedOff() throws {
        let report = SandboxSyncService().run(
            repositoryURL: root,
            config: config(enabled: true, patterns: ["secrets"]),
            targets: [.claude],
            nonoAvailable: true
        )

        XCTAssertEqual(report.plans.first?.mechanism, .nono)

        let profile = try json(".offsend/nono/offsend-claude.json")
        XCTAssertEqual(profile["extends"] as? String, "claude-code")
        let network = try XCTUnwrap(profile["network"] as? [String: Any])
        XCTAssertEqual(network["block"] as? Bool, true)
        let policy = try XCTUnwrap(profile["policy"] as? [String: Any])
        XCTAssertEqual(policy["add_deny_access"] as? [String], ["secrets"])

        // Nested Seatbelt profiles conflict, so exactly one mechanism owns
        // filesystem isolation.
        let settings = try json(".claude/settings.json")
        let sandbox = try XCTUnwrap(settings["sandbox"] as? [String: Any])
        XCTAssertEqual(sandbox["enabled"] as? Bool, false)
        XCTAssertNil(sandbox["filesystem"])

        // Offsend cannot wrap a running process, so it prints the command.
        XCTAssertTrue(report.manualSteps.contains { $0.contains("nono run --profile") })
    }

    func testAllowedDomainsBecomeNonoAllowList() throws {
        _ = SandboxSyncService().run(
            repositoryURL: root,
            config: config(enabled: true, allow: ["registry.npmjs.org"]),
            targets: [.claude],
            nonoAvailable: true
        )

        let profile = try json(".offsend/nono/offsend-claude.json")
        let network = try XCTUnwrap(profile["network"] as? [String: Any])
        XCTAssertEqual(network["allow_domain"] as? [String], ["registry.npmjs.org"])
        XCTAssertNil(network["block"])
    }

    func testCodexAndWindsurfAreReportedRatherThanWritten() {
        let report = SandboxSyncService().run(
            repositoryURL: root,
            config: config(enabled: true),
            targets: [.codex, .windsurf],
            nonoAvailable: false
        )

        XCTAssertEqual(
            report.plans.map(\.mechanism),
            [.codexUserScope, .unavailable]
        )
        XCTAssertTrue(report.changes.isEmpty)
        XCTAssertTrue(report.manualSteps.contains { $0.contains("~/.codex/config.toml") })
    }

    func testRerunIsIdempotent() {
        let service = SandboxSyncService()
        let policy = config(enabled: true, patterns: ["secrets"])
        _ = service.run(repositoryURL: root, config: policy, targets: [.cursor], nonoAvailable: false)
        let second = service.run(repositoryURL: root, config: policy, targets: [.cursor], nonoAvailable: false)

        XCTAssertEqual(second.changes.map(\.kind), [.unchanged])
    }

    func testDryRunReportsWithoutWriting() {
        let report = SandboxSyncService().run(
            repositoryURL: root,
            config: config(enabled: true),
            targets: [.cursor],
            nonoAvailable: false,
            dryRun: true
        )

        XCTAssertEqual(report.changes.map(\.kind), [.created])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursor/sandbox.json").path)
        )
    }

    func testForeignReadonlyTypeIsPreserved() throws {
        let url = root.appendingPathComponent(".cursor/sandbox.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"type":"workspace_readonly"}"#.utf8).write(to: url)

        _ = SandboxSyncService().run(
            repositoryURL: root,
            config: config(enabled: true),
            targets: [.cursor],
            nonoAvailable: false
        )

        XCTAssertEqual(try json(".cursor/sandbox.json")["type"] as? String, "workspace_readonly")
    }

    func testNonoDetectedFromCapabilityFileOfCurrentSandbox() {
        XCTAssertTrue(
            SandboxMechanismResolver.nonoAvailable(
                environment: ["NONO_CAP_FILE": "/tmp/caps.json", "PATH": "/nonexistent"]
            )
        )
        XCTAssertFalse(
            SandboxMechanismResolver.nonoAvailable(environment: ["PATH": "/nonexistent"])
        )
    }

    func testIDEIsNeverWrappedByNono() {
        XCTAssertEqual(
            SandboxMechanismResolver.plan(target: .cursor, nonoAvailable: true).mechanism,
            .cursorNative
        )
    }
}
