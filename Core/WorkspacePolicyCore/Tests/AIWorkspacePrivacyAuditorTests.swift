import XCTest
@testable import WorkspacePolicyCore

final class AIWorkspacePrivacyAuditorTests: XCTestCase {
    private let auditor = AIWorkspacePrivacyAuditor()
    private let fixer = AIWorkspacePrivacyFixer()
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testEmptyDirectoryReportsMissingRequiredRules() throws {
        let directoryURL = try makeTemporaryDirectory()

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertEqual(result.status, .fail)
        XCTAssertTrue(result.missingRequiredRules.contains { $0.rule.id == "cursor-ignore" })
        XCTAssertTrue(result.missingSensitivePatterns.contains { $0.pattern.id == "env-files" })
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testCompleteDefaultPolicyPasses() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeIgnoreFile(at: ".cursorignore", in: directoryURL)
        try writeFile(".cursor/rules/privacy.mdc", in: directoryURL, contents: """
        ---
        alwaysApply: true
        ---
        Never send secrets, credentials, or environment files to AI tools.
        """)

        let recommendedIgnoreFiles = [
            ".aiexclude",
            ".continueignore",
            ".codeiumignore",
            ".claudeignore",
            ".geminiignore",
            ".llmignore",
            ".aiderignore",
            ".clineignore",
            ".rooignore",
            ".zedignore",
            ".codyignore"
        ]
        for path in recommendedIgnoreFiles {
            try writeFile(path, in: directoryURL, contents: "# Tool-specific AI ignore file\n")
        }

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertEqual(result.status, .pass)
        XCTAssertTrue(result.missingRequiredRules.isEmpty)
        XCTAssertTrue(result.missingRecommendedRules.isEmpty, "\(result.missingRecommendedRules.map { $0.rule.id })")
        XCTAssertTrue(result.missingSensitivePatterns.isEmpty, "\(result.missingSensitivePatterns.map { $0.pattern.id })")
        XCTAssertTrue(result.foundRelativePaths.contains(".cursor/rules/privacy.mdc"))
    }

    func testPartialPolicyWarnsWithoutFailingRequiredChecks() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeIgnoreFile(at: ".cursorignore", in: directoryURL)

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertEqual(result.status, .warning)
        XCTAssertTrue(result.missingRequiredRules.isEmpty)
        XCTAssertTrue(result.missingSensitivePatterns.isEmpty)
        XCTAssertTrue(result.missingRecommendedRules.contains { $0.rule.id == "cursor-project-rules" })
    }

    func testFreeTierCoversPopularToolsAndCriticalPatternsOnly() throws {
        let freeRuleIDs = Set(AIWorkspacePrivacyAuditConfiguration.freeTier.rules.map(\.id))
        let freePatternIDs = Set(AIWorkspacePrivacyAuditConfiguration.freeTier.sensitivePatterns.map(\.id))

        let expectedFreeRules: Set<String> = [
            "cursor-ignore",
            "cursor-indexing-ignore",
            "cursor-project-rules",
            "copilot-exclude",
            "claude-ignore",
            "claude-md",
            "agents-md",
            "git-ignore"
        ]
        XCTAssertEqual(freeRuleIDs, expectedFreeRules)

        let proOnlyRuleSamples: Set<String> = [
            "continue-ignore",
            "codeium-ignore",
            "gemini-ignore",
            "llm-ignore",
            "aider-ignore",
            "cline-ignore",
            "roo-ignore",
            "zed-ignore",
            "cody-ignore"
        ]
        XCTAssertTrue(freeRuleIDs.isDisjoint(with: proOnlyRuleSamples))

        let requiredPatternIDs = Set(
            AIWorkspaceSensitivePattern.defaultPatterns
                .filter { $0.severity == .required }
                .map(\.id)
        )
        XCTAssertTrue(
            requiredPatternIDs.isSubset(of: freePatternIDs),
            "All required patterns must be covered by Free; missing: \(requiredPatternIDs.subtracting(freePatternIDs))"
        )

        let proOnlyPatternSamples: Set<String> = [
            "gcp-credentials",
            "azure-credentials",
            "terraform-state",
            "terraform-vars",
            "pkcs12-p12",
            "pkcs12-pfx",
            "pgp-keys",
            "netrc-files",
            "htpasswd-files",
            "docker-config",
            "db-dumps"
        ]
        XCTAssertTrue(freePatternIDs.isDisjoint(with: proOnlyPatternSamples))
    }

    func testFreeTierEmptyDirectoryReportsRequiredChecks() throws {
        let directoryURL = try makeTemporaryDirectory()

        let result = auditor.audit(directoryURL: directoryURL, configuration: .freeTier)

        XCTAssertEqual(result.status, .fail)
        XCTAssertEqual(result.missingRequiredRules.map(\.rule.id), ["cursor-ignore"])
        XCTAssertTrue(result.missingSensitivePatterns.contains { $0.pattern.id == "env-files" })
        XCTAssertTrue(result.missingSensitivePatterns.contains { $0.pattern.id == "ssh-files" })
        XCTAssertFalse(result.missingSensitivePatterns.contains { $0.pattern.id == "gcp-credentials" })
        XCTAssertFalse(result.missingSensitivePatterns.contains { $0.pattern.id == "terraform-state" })
    }

    func testCustomConfigurationCanRequireProjectSpecificRule() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".offsend-aiignore", in: directoryURL, contents: "Private/**\n")
        let configuration = AIWorkspacePrivacyAuditConfiguration(
            rules: [
                AIWorkspacePrivacyRule(
                    id: "offsend-aiignore",
                    toolName: "Offsend",
                    title: ".offsend-aiignore",
                    relativePathPatterns: [".offsend-aiignore"],
                    severity: .required,
                    scansForSensitivePatterns: false,
                    remediation: "Add .offsend-aiignore to define project-specific AI exclusions."
                )
            ],
            sensitivePatterns: []
        )

        let result = auditor.audit(directoryURL: directoryURL, configuration: configuration)

        XCTAssertEqual(result.status, .pass)
        XCTAssertEqual(result.foundRelativePaths, [".offsend-aiignore"])
    }

    func testAuditorSkipsAdditionalDirectoryNamesFromConfiguration() throws {
        let directoryURL = try makeTemporaryDirectory().standardizedFileURL
        try writeFile("vendor/nested.mdc", in: directoryURL, contents: "rule\n")

        let recursiveRule = AIWorkspacePrivacyRule(
            id: "recursive-mdc",
            toolName: "Test",
            title: "recursive .mdc lookup",
            relativePathPatterns: ["**/*.mdc"],
            severity: .recommended,
            scansForSensitivePatterns: false,
            remediation: ""
        )
        let baselineConfig = AIWorkspacePrivacyAuditConfiguration(
            rules: [recursiveRule],
            sensitivePatterns: []
        )
        let baseline = auditor.audit(directoryURL: directoryURL, configuration: baselineConfig)
        let baselineFound = baseline.foundRelativePaths.contains { $0.hasSuffix("vendor/nested.mdc") }
        XCTAssertTrue(baselineFound, "Baseline glob walk should descend into 'vendor/' — got \(baseline.foundRelativePaths)")

        let skippedConfig = AIWorkspacePrivacyAuditConfiguration(
            rules: [recursiveRule],
            sensitivePatterns: [],
            additionalSkippedDirectoryNames: ["vendor"]
        )
        let withSkip = auditor.audit(directoryURL: directoryURL, configuration: skippedConfig)
        let skippedFound = withSkip.foundRelativePaths.contains { $0.hasSuffix("vendor/nested.mdc") }
        XCTAssertFalse(skippedFound, "Skipping 'vendor' should hide its contents — got \(withSkip.foundRelativePaths)")
    }

    func testInvalidPathReturnsReadableError() throws {
        let directoryURL = try makeTemporaryDirectory()
        let missingURL = directoryURL.appendingPathComponent("missing")

        let result = auditor.audit(directoryURL: missingURL)

        XCTAssertEqual(result.status, .fail)
        XCTAssertEqual(result.errors.first?.id, "directory-unavailable")
        XCTAssertTrue(result.ruleFindings.isEmpty)
    }

    func testFixerCreatesDefaultPolicyFilesAndPassesAudit() throws {
        let directoryURL = try makeTemporaryDirectory()
        let initialResult = auditor.audit(directoryURL: directoryURL)

        let fixResult = fixer.fix(result: initialResult)
        let fixedResult = auditor.audit(directoryURL: directoryURL)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertTrue(fixResult.createdRelativePaths.contains(".cursorignore"))
        XCTAssertTrue(fixResult.createdRelativePaths.contains(".cursor/rules/privacy.mdc"))
        XCTAssertEqual(fixedResult.status, .pass)
        XCTAssertTrue(fixedResult.missingRequiredRules.isEmpty)
        XCTAssertTrue(fixedResult.missingSensitivePatterns.isEmpty)
    }

    func testFixerAppendsMissingSensitivePatternsToExistingIgnoreFile() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")

        let initialResult = auditor.audit(directoryURL: directoryURL)
        let fixResult = fixer.fix(result: initialResult)
        let contents = try readFile(".cursorignore", in: directoryURL)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertTrue(contents.contains("*.pem"))
        XCTAssertTrue(contents.contains("*.key"))
        XCTAssertTrue(contents.contains("credentials.json"))
        XCTAssertTrue(contents.contains("secrets.json"))
    }

    func testFixerMergesMissingLinesIntoExistingIgnoreFile() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: "# existing\n.env*\n")

        let initialResult = auditor.audit(directoryURL: directoryURL)
        let fixResult = fixer.fix(result: initialResult)
        let contents = try readFile(".cursorignore", in: directoryURL)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertTrue(fixResult.updatedRelativePaths.contains(".cursorignore"))
        XCTAssertTrue(contents.contains("*.pem"))
        XCTAssertTrue(contents.contains("# existing"))
    }

    func testFixerAppendsSensitivePatternsToAllScanEnabledIgnoreFiles() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile(".aiexclude", in: directoryURL, contents: ".env*\n")

        let initialResult = auditor.audit(directoryURL: directoryURL)
        let fixResult = fixer.fix(result: initialResult)

        let cursorContents = try readFile(".cursorignore", in: directoryURL)
        let copilotContents = try readFile(".aiexclude", in: directoryURL)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertTrue(cursorContents.contains("*.pem"))
        XCTAssertTrue(copilotContents.contains("*.pem"))
    }

    func testConcurrentAppendDoesNotLoseUserLines() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: "# user rule\n.custom/**\n")

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "AIWorkspacePrivacyFixerRaceTests", attributes: .concurrent)
        var errors: [AIWorkspacePrivacyFixResult] = []

        for _ in 0..<20 {
            group.enter()
            queue.async {
                defer { group.leave() }
                let result = self.auditor.audit(directoryURL: directoryURL)
                let fixResult = self.fixer.fix(result: result)
                if !fixResult.errors.isEmpty {
                    errors.append(fixResult)
                }
            }
        }
        group.wait()

        let contents = try readFile(".cursorignore", in: directoryURL)

        XCTAssertTrue(errors.isEmpty, "\(errors.flatMap(\.errors))")
        XCTAssertTrue(contents.contains("# user rule"))
        XCTAssertTrue(contents.contains(".custom/**"))
        XCTAssertTrue(contents.contains("*.pem"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIWorkspacePrivacyAuditorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func writeIgnoreFile(at relativePath: String, in rootURL: URL) throws {
        try writeFile(relativePath, in: rootURL, contents: AIWorkspacePrivacyIgnoreTemplate.contents)
    }

    private func writeFile(_ relativePath: String, in rootURL: URL, contents: String) throws {
        let url = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readFile(_ relativePath: String, in rootURL: URL) throws -> String {
        let url = rootURL.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
