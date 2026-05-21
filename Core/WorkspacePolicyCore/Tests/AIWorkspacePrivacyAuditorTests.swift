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

        for path in [".aiexclude", ".continueignore", ".codeiumignore", ".claudeignore", ".geminiignore", ".llmignore"] {
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

    func testFreeTierConfigurationIgnoresRecommendedRules() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeIgnoreFile(at: ".cursorignore", in: directoryURL)

        let result = auditor.audit(directoryURL: directoryURL, configuration: .freeTier)

        XCTAssertEqual(result.status, .pass)
        XCTAssertEqual(result.ruleFindings.count, 1)
        XCTAssertEqual(result.ruleFindings.first?.rule.id, "cursor-ignore")
        XCTAssertTrue(result.missingRecommendedRules.isEmpty)
        XCTAssertFalse(result.sensitivePatternFindings.contains { $0.pattern.id == "ssh-files" })
    }

    func testFreeTierEmptyDirectoryReportsOnlyRequiredChecks() throws {
        let directoryURL = try makeTemporaryDirectory()

        let result = auditor.audit(directoryURL: directoryURL, configuration: .freeTier)

        XCTAssertEqual(result.status, .fail)
        XCTAssertEqual(result.missingRequiredRules.map(\.rule.id), ["cursor-ignore"])
        XCTAssertTrue(result.missingRecommendedRules.isEmpty)
        XCTAssertTrue(result.missingSensitivePatterns.contains { $0.pattern.id == "env-files" })
        XCTAssertFalse(result.missingSensitivePatterns.contains { $0.pattern.id == "ssh-files" })
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

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIWorkspacePrivacyAuditorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func writeIgnoreFile(at relativePath: String, in rootURL: URL) throws {
        try writeFile(relativePath, in: rootURL, contents: """
        .env*
        *.pem
        *.key
        .ssh/
        .aws/
        credentials.json
        secrets.json
        """)
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
