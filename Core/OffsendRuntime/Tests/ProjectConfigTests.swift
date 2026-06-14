import XCTest
@testable import OffsendRuntime

final class ProjectConfigTests: XCTestCase {
    func testLoadsProjectConfigFromRepositoryRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let yaml = """
        version: 1
        check:
          fail_on: warn
          policy: true
          exclude:
            - "*.lock"
          detectors:
            disable:
              - email
        hooks:
          fail_on: block
          policy: false
        """
        try yaml.write(to: root.appendingPathComponent(".offsend.yml"), atomically: true, encoding: .utf8)

        let config = try XCTUnwrap(ProjectConfigLoader().load(from: root))
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.check?.failOn, "warn")
        XCTAssertEqual(config.check?.policy, true)
        XCTAssertEqual(config.check?.exclude, ["*.lock"])
        XCTAssertEqual(config.check?.detectors?.disable, ["email"])
        XCTAssertEqual(config.hooks?.failOn, "block")
    }

    func testOptionsResolverPrefersCLIOverridesOverConfig() {
        let config = OffsendProjectConfig(
            check: OffsendProjectCheckConfig(failOn: "warn", policy: true)
        )

        let resolved = OptionsResolver.resolveCheckOptions(
            overrides: CLICheckOverrides(
                policySpecified: false,
                policyValue: false,
                failOn: "block"
            ),
            projectConfig: config,
            staged: false
        )

        XCTAssertEqual(resolved.failPolicy, .block)
        XCTAssertTrue(resolved.policy)
    }

    func testOptionsResolverUsesConfigWhenCLIOverridesMissing() {
        let config = OffsendProjectConfig(
            check: OffsendProjectCheckConfig(failOn: "warn", policy: true, exclude: ["*.pem"])
        )

        let resolved = OptionsResolver.resolveCheckOptions(
            overrides: CLICheckOverrides(),
            projectConfig: config,
            staged: false
        )

        XCTAssertEqual(resolved.failPolicy, .warn)
        XCTAssertTrue(resolved.policy)
        XCTAssertEqual(resolved.excludePatterns, ["*.pem"])
    }

    func testPathExcludeMatcherMatchesPatterns() {
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "Package.lock", patterns: ["*.lock"]))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "vendor/foo/bar.swift", patterns: ["vendor/**"]))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(relativePath: "src/main.swift", patterns: ["vendor/**"]))
    }

    func testDoctorReportFailsWhenSettingsUnavailable() {
        let report = OffsendDoctor().run(context: nil)
        XCTAssertFalse(report.isHealthy)
        XCTAssertTrue(report.checks.contains { $0.name == "settings" && $0.status == .fail })
    }

    func testValidatorAcceptsValidConfig() {
        let config = OffsendProjectConfig(
            check: OffsendProjectCheckConfig(
                failOn: "warn",
                policy: true,
                detectors: OffsendProjectDetectorsConfig(disable: ["email", "phone"]),
                dictionaries: [OffsendProjectDictionaryEntry(kind: "client", value: "Acme")]
            ),
            hooks: OffsendProjectHooksConfig(type: "pre-commit", failOn: "block")
        )

        XCTAssertTrue(ProjectConfigValidator.validate(config).isEmpty)
    }

    func testValidatorReportsUnknownValues() {
        let config = OffsendProjectConfig(
            check: OffsendProjectCheckConfig(
                failOn: "explode",
                detectors: OffsendProjectDetectorsConfig(disable: ["email", "phon"]),
                dictionaries: [OffsendProjectDictionaryEntry(kind: "customer", value: "Acme")]
            ),
            hooks: OffsendProjectHooksConfig(type: "post-merge")
        )

        let issues = ProjectConfigValidator.validate(config)
        XCTAssertTrue(issues.contains { $0.contains("check.fail_on") })
        XCTAssertTrue(issues.contains { $0.contains("hooks.type") })
        XCTAssertTrue(issues.contains { $0.contains("phon") })
        XCTAssertTrue(issues.contains { $0.contains("customer") })
    }

    func testValidatorReportsMisplacedDisableKey() {
        let yaml = """
        version: 1
        check:
          fail_on: block
          disable:
            - email
        """

        let issues = ProjectConfigValidator.validateYAMLStructure(yaml)
        XCTAssertTrue(issues.contains { $0.contains("check.disable is ignored") })
    }
}
