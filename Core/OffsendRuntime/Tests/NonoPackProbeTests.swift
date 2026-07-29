import XCTest
@testable import OffsendRuntime

final class NonoPackProbeTests: XCTestCase {
    private var configHome: URL!

    override func setUpWithError() throws {
        configHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("offsend-nono-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: configHome)
    }

    private func probe() -> NonoPackProbe {
        NonoPackProbe(configHome: configHome)
    }

    func testClaudeRequirementMapsToRegistryPack() throws {
        let req = try XCTUnwrap(NonoPackRequirement.forTarget(.claude))
        XCTAssertEqual(req.preferredPack, "nolabs-ai/claude")
        XCTAssertEqual(req.baseProfile, "claude-code")
        XCTAssertTrue(req.acceptedPacks.contains("always-further/claude"))
        XCTAssertEqual(req.pullHint, "nono pull nolabs-ai/claude")
    }

    func testMissingPackIsUnsatisfied() throws {
        let result = try XCTUnwrap(probe().probe(target: .claude))
        XCTAssertFalse(result.isSatisfied)
        XCTAssertTrue(result.missingMessage.contains("nono pull nolabs-ai/claude"))
        XCTAssertTrue(result.missingMessage.contains("nono.sh/registry"))
    }

    func testInstalledNolabsPackSatisfies() throws {
        let dir = configHome
            .appendingPathComponent("nono/packages/nolabs-ai/claude")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let result = try XCTUnwrap(probe().probe(target: .claude))
        XCTAssertTrue(result.isSatisfied)
        XCTAssertEqual(result.installedPack, "nolabs-ai/claude")
    }

    func testLegacyAlwaysFurtherPackStillCounts() throws {
        let dir = configHome
            .appendingPathComponent("nono/packages/always-further/codex")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let result = try XCTUnwrap(probe().probe(target: .codex))
        XCTAssertTrue(result.isSatisfied)
        XCTAssertEqual(result.installedPack, "always-further/codex")
    }

    func testBaseProfileFileSatisfiesWithoutPackDir() throws {
        let profiles = configHome.appendingPathComponent("nono/profiles")
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: profiles.appendingPathComponent("claude-code.json"))

        let result = try XCTUnwrap(probe().probe(target: .claude))
        XCTAssertTrue(result.isSatisfied)
        XCTAssertNil(result.installedPack)
        XCTAssertTrue(result.baseProfilePresent)
    }

    func testLockfilePackagesKeySatisfies() throws {
        let nono = configHome.appendingPathComponent("nono")
        try FileManager.default.createDirectory(at: nono, withIntermediateDirectories: true)
        let json: [String: Any] = [
            "lockfile_version": 1,
            "packages": ["nolabs-ai/claude": ["version": "1.0.0"]],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: nono.appendingPathComponent("packages-lock.json"))

        let result = try XCTUnwrap(probe().probe(target: .claude))
        XCTAssertTrue(result.isSatisfied)
        XCTAssertEqual(result.installedPack, "nolabs-ai/claude")
    }

    func testCursorHasNoPackRequirement() {
        XCTAssertNil(NonoPackRequirement.forTarget(.cursor))
        XCTAssertNil(probe().probe(target: .cursor))
    }

    func testSandboxChecksFailWhenPackMissing() throws {
        let report = SandboxSyncService.Report(
            enabled: true,
            plans: [
                SandboxMechanismResolver.plan(target: .claude, nonoAvailable: true),
            ]
        )
        let missing = NonoPackProbeResult(
            requirement: try XCTUnwrap(NonoPackRequirement.forTarget(.claude)),
            installedPack: nil,
            baseProfilePresent: false
        )
        let checks = OffsendDoctor.sandboxChecks(
            report: report,
            audit: [],
            packResults: [missing]
        )
        let packCheck = checks.first { $0.name == "sandbox-nono-pack-claude" }
        XCTAssertEqual(packCheck?.status, .fail)
        XCTAssertTrue(packCheck?.message.contains("nono pull nolabs-ai/claude") == true)
    }
}
