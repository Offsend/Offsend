import XCTest
import WorkspacePolicyCore
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
          ignore_exclude: true
        """
        try yaml.write(to: root.appendingPathComponent(".offsend.yml"), atomically: true, encoding: .utf8)

        let config = try XCTUnwrap(ProjectConfigLoader().load(from: root))
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.check?.failOn, "warn")
        XCTAssertEqual(config.check?.policy, true)
        XCTAssertEqual(config.check?.exclude, ["*.lock"])
        XCTAssertEqual(config.check?.detectors?.disable, ["email"])
        XCTAssertEqual(config.hooks?.failOn, "block")
        XCTAssertEqual(config.hooks?.ignoreExclude, true)
        XCTAssertTrue(config.hooks?.ignoresCheckExclude ?? false)
    }

    func testHooksIgnoreExcludeDefaultsToFalse() {
        XCTAssertFalse(OffsendProjectHooksConfig().ignoresCheckExclude)
        XCTAssertFalse(OffsendProjectHooksConfig(ignoreExclude: false).ignoresCheckExclude)
        // ignore_exclude must be a known key for the structure validator.
        let issues = ProjectConfigValidator.validateYAMLStructure(
            """
            version: 1
            hooks:
              ignore_exclude: false
            """
        )
        XCTAssertFalse(issues.contains { $0.contains("ignore_exclude") }, issues.joined(separator: "; "))
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

    func testPathExcludeMatcherNestedGlobs() {
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "packages/ui/node_modules/lodash/index.js",
            patterns: ["**/node_modules/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "app/module/build/outputs/app.apk",
            patterns: ["**/build/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "pkg.egg-info/PKG-INFO",
            patterns: ["**/*.egg-info/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "src/pkg.egg-info/dependency_links.txt",
            patterns: ["*.egg-info/**"]
        ))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(
            relativePath: "src/main.swift",
            patterns: ["**/node_modules/**", "**/build/**"]
        ))
    }

    func testPathExcludeMatcherShouldSkipDirectory() {
        XCTAssertTrue(PathExcludeMatcher.shouldSkipDirectory(
            relativePath: "packages/ui/node_modules",
            patterns: ["**/node_modules/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.shouldSkipDirectory(relativePath: ".git", patterns: []))
        XCTAssertFalse(PathExcludeMatcher.shouldSkipDirectory(
            relativePath: "src",
            patterns: ["**/node_modules/**"]
        ))
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

    func testIgnoreToolsParsing() {
        XCTAssertNil(OffsendProjectIgnoreConfig().toolIDs)
        XCTAssertNil(OffsendProjectIgnoreConfig(tools: []).toolIDs)
        XCTAssertNil(OffsendProjectIgnoreConfig(tools: ["nope"]).toolIDs)
        XCTAssertEqual(
            OffsendProjectIgnoreConfig(tools: ["Cursor", " claude ", "nope"]).toolIDs,
            [.cursor, .claude]
        )
        XCTAssertEqual(OffsendProjectIgnoreConfig(tools: ["nope", "cursor"]).unknownToolSlugs, ["nope"])
    }

    func testValidatorReportsUnknownIgnoreTools() {
        let config = OffsendProjectConfig(
            ignore: OffsendProjectIgnoreConfig(tools: ["cursor", "sublime"])
        )

        let issues = ProjectConfigValidator.validate(config)
        XCTAssertTrue(issues.contains { $0.contains("ignore.tools") && $0.contains("sublime") })
        XCTAssertTrue(ProjectConfigValidator.validate(
            OffsendProjectConfig(ignore: OffsendProjectIgnoreConfig(tools: ["cursor", "claude"]))
        ).isEmpty)
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

    func testTemplatesResolveAlwaysIncludesCommon() throws {
        let ids = try ProjectConfigTemplates.resolve(rawValues: [])
        XCTAssertEqual(ids, [.common])

        let withNode = try ProjectConfigTemplates.resolve(rawValues: ["node"])
        XCTAssertEqual(withNode, [.common, .node])
    }

    func testTemplatesResolveCSVAndDedupe() throws {
        let ids = try ProjectConfigTemplates.resolve(rawValues: ["node,swift", "swift", "tuist"])
        XCTAssertEqual(ids, [.common, .node, .swift, .tuist])
    }

    func testTemplatesResolveAliasesAndCaseInsensitive() throws {
        let ids = try ProjectConfigTemplates.resolve(rawValues: ["JS", "ios", "TypeScript"])
        XCTAssertEqual(ids, [.common, .node, .swift])
    }

    func testTemplatesResolveUnknownID() {
        XCTAssertThrowsError(try ProjectConfigTemplates.resolve(rawValues: ["nodejs"])) { error in
            guard let templateError = error as? ProjectConfigTemplateError else {
                return XCTFail("Expected ProjectConfigTemplateError")
            }
            XCTAssertEqual(templateError, .unknownTemplate("nodejs"))
        }
    }

    func testTemplatesExcludePatternsIncludeNodeModules() {
        let patterns = ProjectConfigTemplates.excludePatterns(for: [.node])
        XCTAssertTrue(patterns.contains("*.lock"))
        XCTAssertTrue(patterns.contains("**/node_modules/**"))
        XCTAssertTrue(patterns.contains("package-lock.json"))
        XCTAssertTrue(patterns.contains("pnpm-lock.yaml"))
        XCTAssertTrue(patterns.contains("bun.lock"))
        XCTAssertTrue(patterns.contains(".offsend/hooks/**"))
        XCTAssertEqual(patterns.first, "*.lock")
    }

    func testTemplatesExcludePatternsUnionDedupe() {
        let patterns = ProjectConfigTemplates.excludePatterns(for: [.swift, .tuist, .java, .android])
        XCTAssertTrue(patterns.contains("**/DerivedData/**"))
        XCTAssertTrue(patterns.contains("Package.resolved"))
        XCTAssertFalse(patterns.contains("**/Info.plist"))
        XCTAssertTrue(patterns.contains("**/Tuist/.build/**"))
        XCTAssertTrue(patterns.contains(".package.resolved"))
        XCTAssertEqual(patterns.filter { $0 == "**/.gradle/**" }.count, 1)
        XCTAssertEqual(patterns.filter { $0 == "**/build/**" }.count, 1)
        XCTAssertEqual(Set(patterns).count, patterns.count)
    }

    func testTemplatesMergeExcludeIntoExistingYAML() throws {
        let existing = """
        version: 1

        check:
          fail_on: block
          exclude:
            - "*.lock"
            - "custom/**"
          detectors:
            disable:
              - email

        hooks:
          type: pre-commit
        """

        let result = try ProjectConfigTemplates.mergingExclude(
            intoYAML: existing,
            patterns: ["**/node_modules/**", "*.lock", "**/dist/**"]
        )

        XCTAssertEqual(result.added, ["**/node_modules/**", "**/dist/**"])
        XCTAssertTrue(result.yaml.contains("custom/**"))
        XCTAssertTrue(result.yaml.contains("**/node_modules/**"))
        XCTAssertTrue(result.yaml.contains("detectors:"))
        XCTAssertTrue(result.yaml.contains("- email"))
    }

    func testTemplatesRenderYAMLContainsExcludeAndLoads() throws {
        let yaml = ProjectConfigTemplates.renderYAML(
            templates: [.node],
            ignoreCommit: false,
            hooksPublish: false
        )
        XCTAssertTrue(yaml.contains("**/node_modules/**"))
        XCTAssertTrue(yaml.contains("# templates: common, node"))
        XCTAssertTrue(yaml.contains("ignore:"))
        XCTAssertTrue(yaml.contains("commit: false"))
        XCTAssertTrue(yaml.contains("publish: false"))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try yaml.write(to: root.appendingPathComponent(".offsend.yml"), atomically: true, encoding: .utf8)

        let config = try XCTUnwrap(ProjectConfigLoader().load(from: root))
        XCTAssertTrue(config.check?.exclude?.contains("**/node_modules/**") == true)
        XCTAssertTrue(config.check?.exclude?.contains("*.lock") == true)
        XCTAssertEqual(config.ignore?.commit, false)
        XCTAssertEqual(config.hooks?.publish, false)
        let ignorePatterns = try XCTUnwrap(config.ignore?.patterns)
        XCTAssertEqual(ignorePatterns, AIWorkspacePrivacyIgnoreTemplate.defaultPatterns)
        XCTAssertTrue(ignorePatterns.contains(".env*"))
        XCTAssertTrue(ignorePatterns.contains("*.pem"))
    }

    func testParseYesNoDefaults() {
        XCTAssertEqual(ProjectConfigTemplates.parseYesNo("", defaultYes: true), true)
        XCTAssertEqual(ProjectConfigTemplates.parseYesNo("n", defaultYes: true), false)
        XCTAssertEqual(ProjectConfigTemplates.parseYesNo("yes", defaultYes: false), true)
        XCTAssertNil(ProjectConfigTemplates.parseYesNo("maybe", defaultYes: true))
    }

    func testTemplatesListTextIncludesAliases() {
        let text = ProjectConfigTemplates.listTemplatesText()
        XCTAssertTrue(text.contains("node"))
        XCTAssertTrue(text.contains("js"))
        XCTAssertTrue(text.contains("ios"))
    }
}

