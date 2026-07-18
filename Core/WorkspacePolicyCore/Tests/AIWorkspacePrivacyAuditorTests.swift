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

        XCTAssertEqual(result.status, .warning)
        XCTAssertTrue(result.missingRequiredRules.contains { $0.rule.id == "cursor-ignore" })
        XCTAssertTrue(result.missingSensitivePatterns.isEmpty)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testCompleteDefaultPolicyPasses() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeIgnoreFile(at: ".cursorignore", in: directoryURL)
        // Legacy rule file from older releases still satisfies cursor-project-rules.
        try writeFile(".cursor/rules/privacy.mdc", in: directoryURL, contents: """
        ---
        alwaysApply: true
        ---
        Never send secrets, credentials, or environment files to AI tools.
        """)
        try writeFile(
            ".claude/rules/offsend_privacy.md",
            in: directoryURL,
            contents: AIWorkspacePrivacyDefaultFixes.claudePrivacyRuleContents
        )

        let recommendedIgnoreFiles = [
            ".cursorindexingignore",
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

    func testEmptyDirectoryReportsRequiredChecks() throws {
        let directoryURL = try makeTemporaryDirectory()

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertEqual(result.status, .warning)
        XCTAssertEqual(result.missingRequiredRules.map(\.rule.id), ["cursor-ignore"])
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
        XCTAssertTrue(result.isDirectoryUnavailable)
        XCTAssertTrue(result.ruleFindings.isEmpty)
    }

    func testWorkspaceDirectoryAvailabilityDetectsMissingDirectory() throws {
        let directoryURL = try makeTemporaryDirectory()
        let missingURL = directoryURL.appendingPathComponent("missing")

        XCTAssertTrue(WorkspaceDirectoryAvailability.isReadableDirectory(at: directoryURL))
        XCTAssertFalse(WorkspaceDirectoryAvailability.isReadableDirectory(at: missingURL))
    }

    func testFixerCreatesDefaultPolicyFilesAndPassesAudit() throws {
        let directoryURL = try makeTemporaryDirectory()
        let initialResult = auditor.audit(directoryURL: directoryURL)

        let fixResult = fixer.fix(result: initialResult)
        let fixedResult = auditor.audit(directoryURL: directoryURL)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertTrue(fixResult.createdRelativePaths.contains(".cursorignore"))
        XCTAssertTrue(fixResult.createdRelativePaths.contains(".cursor/rules/offsend_privacy.mdc"))
        XCTAssertTrue(fixResult.createdRelativePaths.contains(".claude/rules/offsend_privacy.md"))
        XCTAssertEqual(fixedResult.status, .pass)
        XCTAssertTrue(fixedResult.missingRequiredRules.isEmpty)
        XCTAssertTrue(fixedResult.missingSensitivePatterns.isEmpty)
    }

    func testFixerAppendsMissingSensitivePatternsToExistingIgnoreFile() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")
        try writeFile("secret.key", in: directoryURL, contents: "key")
        try writeFile("credentials.json", in: directoryURL, contents: "{}")
        try writeFile("secrets.json", in: directoryURL, contents: "{}")

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
        try writeFile("server.pem", in: directoryURL, contents: "key")

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
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let initialResult = auditor.audit(directoryURL: directoryURL)
        let fixResult = fixer.fix(result: initialResult)

        let cursorContents = try readFile(".cursorignore", in: directoryURL)
        let copilotContents = try readFile(".aiexclude", in: directoryURL)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertTrue(cursorContents.contains("*.pem"))
        XCTAssertTrue(copilotContents.contains("*.pem"))
    }

    func testFixerAppliesOnlySelectedRulesAndPatterns() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")
        try writeFile("secret.key", in: directoryURL, contents: "key")

        let initialResult = auditor.audit(directoryURL: directoryURL)
        let selectionWithoutRuleFile = AIWorkspacePrivacyFixSelection(
            ruleIDs: [],
            patternIDs: ["pem-files"]
        )
        let skippedFixResult = fixer.fix(result: initialResult, selection: selectionWithoutRuleFile)

        XCTAssertEqual(skippedFixResult.createdRelativePaths, [])
        XCTAssertEqual(skippedFixResult.updatedRelativePaths, [])
        XCTAssertEqual(skippedFixResult.errors.map(\.id), ["no-pattern-target-files"])
        XCTAssertEqual(try readFile(".cursorignore", in: directoryURL), ".env*\n")

        let selectionWithRuleFile = AIWorkspacePrivacyFixSelection(
            ruleIDs: ["cursor-ignore"],
            patternIDs: ["pem-files"]
        )
        let fixResult = fixer.fix(result: initialResult, selection: selectionWithRuleFile)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertTrue(fixResult.updatedRelativePaths.contains(".cursorignore"))
        XCTAssertTrue(fixResult.createdRelativePaths.isEmpty)

        let cursorContents = try readFile(".cursorignore", in: directoryURL)
        XCTAssertTrue(cursorContents.contains("*.pem"))
        XCTAssertFalse(cursorContents.contains("*.key"))
    }

    func testFixerAppliesOnlySelectedRuleFiles() throws {
        let directoryURL = try makeTemporaryDirectory()
        let initialResult = auditor.audit(directoryURL: directoryURL)

        let selection = AIWorkspacePrivacyFixSelection(
            ruleIDs: ["cursor-project-rules"],
            patternIDs: []
        )
        let fixResult = fixer.fix(result: initialResult, selection: selection)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertTrue(fixResult.createdRelativePaths.contains(".cursor/rules/offsend_privacy.mdc"))
        XCTAssertFalse(fixResult.createdRelativePaths.contains(".cursorignore"))
    }

    func testFixPlannerDefaultSelectionSelectsExposureGapAndAllPatterns() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")
        try writeFile("secret.key", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)
        let items = AIWorkspacePrivacyFixPlanner.fixItems(for: result, configuration: .default)
        let selection = AIWorkspacePrivacyFixPlanner.defaultSelection(for: items, result: result)

        XCTAssertEqual(selection.ruleIDs, ["cursor-ignore"])
        XCTAssertEqual(selection.patternIDs, Set(["pem-files", "key-files"]))
    }

    func testFixPlannerScenarioDetectsExistingAndMissingPolicyFiles() throws {
        let emptyDirectory = try makeTemporaryDirectory()
        let emptyResult = auditor.audit(directoryURL: emptyDirectory)
        XCTAssertEqual(AIWorkspacePrivacyFixPlanner.fixScenario(for: emptyResult), .noPolicyFiles)

        let existingDirectory = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: existingDirectory, contents: ".env*\n")
        try writeFile("server.pem", in: existingDirectory, contents: "key")
        let existingResult = auditor.audit(directoryURL: existingDirectory)
        XCTAssertEqual(AIWorkspacePrivacyFixPlanner.fixScenario(for: existingResult), .existingPolicyFiles)

        let existingItems = AIWorkspacePrivacyFixPlanner.fixItems(for: existingResult, configuration: .default)
        let ruleItems = existingItems.filter {
            if case .ruleFile = $0.kind { return true }
            return false
        }
        XCTAssertFalse(AIWorkspacePrivacyFixPlanner.exposureGapRuleItems(from: ruleItems, result: existingResult).isEmpty)
        XCTAssertFalse(AIWorkspacePrivacyFixPlanner.missingRuleItems(from: ruleItems, result: existingResult).isEmpty)

        let missingIgnoreFiles = AIWorkspacePrivacyFixPlanner.missingIgnoreFileItems(
            for: existingResult,
            configuration: .default
        )
        XCTAssertTrue(missingIgnoreFiles.contains { $0.id == "claude-ignore" })
        XCTAssertTrue(missingIgnoreFiles.contains { $0.id == "copilot-exclude" })
        XCTAssertFalse(missingIgnoreFiles.contains { $0.id == "cursor-ignore" })
        XCTAssertFalse(missingIgnoreFiles.contains { $0.id == "cursor-project-rules" })

        let missingOnlyItems = AIWorkspacePrivacyFixPlanner.fixItems(for: emptyResult, configuration: .default)
        let missingOnlyRuleItems = missingOnlyItems.filter {
            if case .ruleFile = $0.kind { return true }
            return false
        }
        XCTAssertTrue(AIWorkspacePrivacyFixPlanner.exposureGapRuleItems(from: missingOnlyRuleItems, result: emptyResult).isEmpty)
        XCTAssertFalse(AIWorkspacePrivacyFixPlanner.missingRuleItems(from: missingOnlyRuleItems, result: emptyResult).isEmpty)
    }

    func testFixPlannerDefaultSelectionMatchesAllFixItems() throws {
        let directoryURL = try makeTemporaryDirectory()
        let initialResult = auditor.audit(directoryURL: directoryURL)
        let items = AIWorkspacePrivacyFixPlanner.fixItems(for: initialResult, configuration: .default)
        let selection = AIWorkspacePrivacyFixPlanner.defaultSelection(for: items, result: initialResult)

        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(selection.ruleIDs.count + selection.patternIDs.count, items.count)
        XCTAssertEqual(
            AIWorkspacePrivacyFixPlanner.selection(from: Set(items.map(\.id)), in: items),
            selection
        )
    }

    func testFixPlannerListsEachMissingPatternAsSelectableItem() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")
        try writeFile("secret.key", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)
        let items = AIWorkspacePrivacyFixPlanner.fixItems(for: result, configuration: .default)
        let patternItemIDs = Set(items.compactMap { item -> String? in
            guard case .sensitivePattern = item.kind else { return nil }
            return item.id
        })

        XCTAssertFalse(patternItemIDs.isEmpty)
        XCTAssertEqual(patternItemIDs, Set(result.missingSensitivePatterns.map(\.pattern.id)))
        XCTAssertTrue(patternItemIDs.contains("pem-files"))
        XCTAssertTrue(patternItemIDs.contains("key-files"))
    }

    func testFixPlannerSelectionMapsIndividualPatternIDs() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")
        try writeFile("secret.key", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)
        let items = AIWorkspacePrivacyFixPlanner.fixItems(for: result, configuration: .default)
        let selectedIDs: Set<String> = ["pem-files", "key-files"]

        let selection = AIWorkspacePrivacyFixPlanner.selection(from: selectedIDs, in: items)

        XCTAssertEqual(selection.patternIDs, selectedIDs)
        XCTAssertTrue(selection.ruleIDs.isEmpty)
    }

    func testFixPlannerPlannedPathsForPatternOnlySelectionRequiresSelectedIgnoreFile() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile(".aiexclude", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)
        let patternOnlySelection = AIWorkspacePrivacyFixSelection(
            ruleIDs: [],
            patternIDs: ["pem-files"]
        )

        XCTAssertTrue(
            AIWorkspacePrivacyFixPlanner.plannedRelativePaths(
                for: result,
                configuration: .default,
                selection: patternOnlySelection
            ).isEmpty
        )

        let linkedSelection = AIWorkspacePrivacyFixSelection(
            ruleIDs: ["cursor-ignore", "copilot-exclude"],
            patternIDs: ["pem-files"]
        )
        let plannedPaths = AIWorkspacePrivacyFixPlanner.plannedRelativePaths(
            for: result,
            configuration: .default,
            selection: linkedSelection
        )

        XCTAssertEqual(Set(plannedPaths), [".cursorignore", ".aiexclude"])
        XCTAssertFalse(plannedPaths.contains(".claudeignore"))
    }

    func testFixerAppliesOnlyTwoSelectedPatterns() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")
        try writeFile("secret.key", in: directoryURL, contents: "key")

        let initialResult = auditor.audit(directoryURL: directoryURL)
        let selection = AIWorkspacePrivacyFixSelection(
            ruleIDs: ["cursor-ignore"],
            patternIDs: ["pem-files", "key-files"]
        )
        let fixResult = fixer.fix(result: initialResult, selection: selection)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertEqual(fixResult.createdRelativePaths, [])
        XCTAssertEqual(fixResult.updatedRelativePaths, [".cursorignore"])

        let contents = try readFile(".cursorignore", in: directoryURL)
        XCTAssertTrue(contents.contains("*.pem"))
        XCTAssertTrue(contents.contains("*.key"))
        XCTAssertFalse(contents.contains("credentials.json"))
        XCTAssertFalse(contents.contains("secrets.json"))
    }

    func testFixerSkipsAllPatternsWhenPatternSelectionIsEmpty() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        let originalContents = try readFile(".cursorignore", in: directoryURL)

        let initialResult = auditor.audit(directoryURL: directoryURL)
        let selection = AIWorkspacePrivacyFixSelection(ruleIDs: [], patternIDs: [])
        let fixResult = fixer.fix(result: initialResult, selection: selection)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertFalse(fixResult.didChangeFiles)
        XCTAssertEqual(try readFile(".cursorignore", in: directoryURL), originalContents)
    }

    func testFixerAppliesPatternsIncrementally() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")
        try writeFile("secret.key", in: directoryURL, contents: "key")

        let initialResult = auditor.audit(directoryURL: directoryURL)
        let pemOnly = AIWorkspacePrivacyFixSelection(ruleIDs: ["cursor-ignore"], patternIDs: ["pem-files"])
        let pemFixResult = fixer.fix(result: initialResult, selection: pemOnly)
        XCTAssertTrue(pemFixResult.errors.isEmpty, "\(pemFixResult.errors)")

        let afterPemContents = try readFile(".cursorignore", in: directoryURL)
        XCTAssertTrue(afterPemContents.contains("*.pem"))
        XCTAssertFalse(afterPemContents.contains("*.key"))

        let afterPemAudit = auditor.audit(directoryURL: directoryURL)
        XCTAssertFalse(afterPemAudit.missingSensitivePatterns.contains { $0.pattern.id == "pem-files" })
        XCTAssertTrue(afterPemAudit.missingSensitivePatterns.contains { $0.pattern.id == "key-files" })

        let keyOnly = AIWorkspacePrivacyFixSelection(ruleIDs: ["cursor-ignore"], patternIDs: ["key-files"])
        let keyFixResult = fixer.fix(result: afterPemAudit, selection: keyOnly)
        XCTAssertTrue(keyFixResult.errors.isEmpty, "\(keyFixResult.errors)")

        let finalContents = try readFile(".cursorignore", in: directoryURL)
        XCTAssertTrue(finalContents.contains("*.pem"))
        XCTAssertTrue(finalContents.contains("*.key"))
        XCTAssertFalse(finalContents.contains("credentials.json"))
    }

    func testFixerPatternSelectionDoesNotCreateUnselectedIgnoreFiles() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let initialResult = auditor.audit(directoryURL: directoryURL)
        let selection = AIWorkspacePrivacyFixSelection(ruleIDs: ["cursor-ignore"], patternIDs: ["pem-files"])
        let fixResult = fixer.fix(result: initialResult, selection: selection)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(".aiexclude").path))
        XCTAssertFalse(fixResult.createdRelativePaths.contains(".aiexclude"))
    }

    func testFixerPatternsOnEmptyFolderRequireSelectedIgnoreRule() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile("server.pem", in: directoryURL, contents: "key")
        try writeFile("secret.key", in: directoryURL, contents: "key")
        let initialResult = auditor.audit(directoryURL: directoryURL)

        let patternOnly = AIWorkspacePrivacyFixSelection(ruleIDs: [], patternIDs: ["pem-files", "key-files"])
        let skippedFixResult = fixer.fix(result: initialResult, selection: patternOnly)

        XCTAssertFalse(skippedFixResult.didChangeFiles)
        XCTAssertEqual(skippedFixResult.errors.map(\.id), ["no-pattern-target-files"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(".cursorignore").path))

        let linkedSelection = AIWorkspacePrivacyFixSelection(
            ruleIDs: ["cursor-ignore"],
            patternIDs: ["pem-files", "key-files"]
        )
        let fixResult = fixer.fix(result: initialResult, selection: linkedSelection)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertTrue(fixResult.createdRelativePaths.contains(".cursorignore"))

        let contents = try readFile(".cursorignore", in: directoryURL)
        XCTAssertTrue(contents.contains("*.pem"))
        XCTAssertTrue(contents.contains("*.key"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(".aiexclude").path))
    }

    func testFixerPatternsApplyOnlyToSelectedIgnoreFiles() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile(".aiexclude", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let initialResult = auditor.audit(directoryURL: directoryURL)
        let selection = AIWorkspacePrivacyFixSelection(
            ruleIDs: ["cursor-ignore"],
            patternIDs: ["pem-files"]
        )
        let fixResult = fixer.fix(result: initialResult, selection: selection)

        XCTAssertTrue(fixResult.errors.isEmpty, "\(fixResult.errors)")
        XCTAssertEqual(Set(fixResult.updatedRelativePaths), [".cursorignore"])

        let cursorContents = try readFile(".cursorignore", in: directoryURL)
        let copilotContents = try readFile(".aiexclude", in: directoryURL)

        XCTAssertTrue(cursorContents.contains("*.pem"))
        XCTAssertFalse(copilotContents.contains("*.pem"))
    }

    func testFixPlannerPatternTargetsFollowSelectedIgnoreRules() throws {
        let directoryURL = try makeTemporaryDirectory()
        let result = auditor.audit(directoryURL: directoryURL)

        let emptyTargets = AIWorkspacePrivacyFixPlanner.patternTargetRelativePaths(
            for: result,
            configuration: .default,
            selection: AIWorkspacePrivacyFixSelection(ruleIDs: [], patternIDs: ["pem-files"])
        )
        XCTAssertTrue(emptyTargets.isEmpty)

        let cursorTargets = AIWorkspacePrivacyFixPlanner.patternTargetRelativePaths(
            for: result,
            configuration: .default,
            selection: AIWorkspacePrivacyFixSelection(ruleIDs: ["cursor-ignore"], patternIDs: ["pem-files"])
        )
        XCTAssertEqual(cursorTargets, [".cursorignore"])
    }

    func testFixPlannerIncludesExposureGapPolicyTargetsAndSortsRequiredPatternsFirst() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile(".claudeignore", in: directoryURL, contents: AIWorkspacePrivacyIgnoreTemplate.contents)
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)
        let items = AIWorkspacePrivacyFixPlanner.fixItems(for: result, configuration: .default)

        XCTAssertEqual(items.first?.id, "pem-files")
        XCTAssertTrue(items.contains { $0.id == "cursor-ignore" })
        XCTAssertFalse(items.contains { $0.id == "claude-ignore" })

        let selection = AIWorkspacePrivacyFixPlanner.defaultSelection(for: items, result: result)
        XCTAssertEqual(selection.patternIDs, ["pem-files"])
        let targets = AIWorkspacePrivacyFixPlanner.patternTargetRelativePaths(
            for: result,
            configuration: .default,
            selection: selection
        )
        XCTAssertEqual(targets, [".cursorignore"])

        let fixResult = fixer.fix(result: result, selection: selection)
        XCTAssertTrue(fixResult.errors.isEmpty)
        XCTAssertEqual(try readFile(".cursorignore", in: directoryURL), ".env*\n*.pem\n")
    }

    func testConcurrentAppendDoesNotLoseUserLines() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: "# user rule\n.custom/**\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "AIWorkspacePrivacyFixerRaceTests", attributes: .concurrent)
        let errorCollector = FixErrorCollector()
        let auditor = auditor
        let fixer = fixer

        for _ in 0..<20 {
            group.enter()
            queue.async {
                defer { group.leave() }
                let result = auditor.audit(directoryURL: directoryURL)
                let fixResult = fixer.fix(result: result)
                if !fixResult.errors.isEmpty {
                    errorCollector.append(fixResult)
                }
            }
        }
        group.wait()

        let contents = try readFile(".cursorignore", in: directoryURL)

        XCTAssertTrue(errorCollector.results.isEmpty, "\(errorCollector.results.flatMap(\.errors))")
        XCTAssertTrue(contents.contains("# user rule"))
        XCTAssertTrue(contents.contains(".custom/**"))
        XCTAssertTrue(contents.contains("*.pem"))
    }

    func testScopedSensitivePatternIsNotTreatedAsGlobalCoverage() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\nsecrets/*.pem\n")
        try writeFile("id.pem", in: directoryURL, contents: "key")
        try writeFile("secrets/nested.pem", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertFalse(
            result.missingSensitivePatterns.contains {
                $0.pattern.id == "pem-files" && $0.exposedRelativePaths.contains("secrets/nested.pem")
            },
            "`secrets/*.pem` must cover PEM files inside `secrets/`."
        )
        XCTAssertTrue(
            result.missingSensitivePatterns.contains {
                $0.pattern.id == "pem-files" && $0.exposedRelativePaths.contains("id.pem")
            },
            "Root-level PEM files must stay exposed when only a scoped ignore line exists."
        )
    }

    func testSlashlessIgnoreLineCoversNestedSensitiveFiles() throws {
        // Regression: gitignore semantics mean `*.pem` covers PEM files at any depth,
        // so `prepare`'s template (which writes `*.pem`) silences nested findings too.
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n*.pem\n")
        try writeFile("certs/server.pem", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertFalse(
            result.missingSensitivePatterns.contains { $0.pattern.id == "pem-files" },
            "`*.pem` must cover nested PEM files, matching how AI tools read ignore files."
        )
    }

    func testTrailingSlashIsNormalizedForCoverage() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n.ssh\n")
        try writeFile(".ssh/id_rsa", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertFalse(
            result.missingSensitivePatterns.contains { $0.pattern.id == "ssh-files" },
            "`.ssh` must ignore SSH material under the directory."
        )
    }

    func testScopedEnvPatternDoesNotCoverEnvFiles() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: "config/.env\n")
        try writeFile(".env", in: directoryURL, contents: "SECRET=1")
        try writeFile("config/.env", in: directoryURL, contents: "SECRET=1")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertTrue(
            result.missingSensitivePatterns.contains {
                $0.pattern.id == "env-files" && $0.exposedRelativePaths.contains(".env")
            },
            "A single nested env ignore line must not cover root `.env`."
        )
        XCTAssertFalse(
            result.missingSensitivePatterns.contains {
                $0.pattern.id == "env-files" && $0.exposedRelativePaths.contains("config/.env")
            }
        )
    }

    func testExactAcceptedPatternCountsAsCoverage() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n*.pem\n**/*.key\n")
        try writeFile("id.pem", in: directoryURL, contents: "key")
        try writeFile("nested/secret.key", in: directoryURL, contents: "key")
        try writeFile(".env.local", in: directoryURL, contents: "SECRET=1")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertTrue(result.missingSensitivePatterns.isEmpty)
    }

    func testExposedFileWithoutIgnorePatternIsReported() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertEqual(
            result.missingSensitivePatterns.map(\.pattern.id),
            ["pem-files"]
        )
        XCTAssertEqual(result.missingSensitivePatterns.first?.exposedRelativePaths, ["server.pem"])
    }

    func testNoSensitiveFilesOnDiskProducesNoPatternFindings() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertTrue(result.missingSensitivePatterns.isEmpty)
    }

    func testCanonicalIgnoreLinePrefersSingleStarForm() {
        let pattern = AIWorkspaceSensitivePattern(
            id: "pem",
            title: "PEM",
            acceptedPatterns: ["*.pem", "**/*.pem"],
            remediation: ""
        )
        XCTAssertEqual(pattern.canonicalIgnoreLine, "*.pem")
    }

    func testCanonicalIgnoreLineFallsBackToFirstNonRecursiveForm() {
        let pattern = AIWorkspaceSensitivePattern(
            id: "ssh",
            title: "SSH",
            acceptedPatterns: [".ssh/", "**/.ssh/"],
            remediation: ""
        )
        XCTAssertEqual(pattern.canonicalIgnoreLine, ".ssh/")
    }

    func testCanonicalIgnoreLineFallsBackToFirstFormWhenOnlyRecursive() {
        let pattern = AIWorkspaceSensitivePattern(
            id: "recursive-only",
            title: "Recursive only",
            acceptedPatterns: ["**/*.pem"],
            remediation: ""
        )
        XCTAssertEqual(pattern.canonicalIgnoreLine, "**/*.pem")
    }

    func testBuildOutputDirectoryIsSkipped() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile("build/cache/app.sqlite", in: directoryURL, contents: "db")
        try writeFile("data/app.sqlite", in: directoryURL, contents: "db")

        let result = auditor.audit(directoryURL: directoryURL)
        let exposed = result.missingSensitivePatterns
            .first { $0.pattern.id == "local-databases" }?
            .exposedRelativePaths ?? []

        XCTAssertTrue(exposed.contains("data/app.sqlite"))
        XCTAssertFalse(
            exposed.contains { $0.hasPrefix("build/") },
            "build/ output artifacts must be skipped, got \(exposed)"
        )
    }

    func testDotDbFilesAreNotFlaggedAsLocalDatabases() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile("data/metadata.db", in: directoryURL, contents: "db")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertFalse(
            result.missingSensitivePatterns.contains { $0.pattern.id == "local-databases" },
            "*.db is too ambiguous (e.g. Xcode build.db) and must not be flagged."
        )
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

    func testAuditDeltaUpdatesMissingRuleWhenIgnoreFileDeleted() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeIgnoreFile(at: ".cursorignore", in: directoryURL)

        let baseline = auditor.audit(directoryURL: directoryURL)
        XCTAssertEqual(baseline.status, .warning)

        try FileManager.default.removeItem(at: directoryURL.appendingPathComponent(".cursorignore"))

        let deltaResult = auditor.auditDelta(
            directoryURL: directoryURL,
            changedRelativePaths: [".cursorignore"],
            previousResult: baseline
        )

        XCTAssertNotNil(deltaResult)
        XCTAssertEqual(deltaResult?.status, .warning)
        XCTAssertTrue(deltaResult?.missingRequiredRules.contains { $0.rule.id == "cursor-ignore" } == true)
    }

    func testDeletingIgnoreFileWithSensitiveFilesRemainingFailsAudit() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeIgnoreFile(at: ".cursorignore", in: directoryURL)
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let baseline = auditor.audit(directoryURL: directoryURL)
        XCTAssertTrue(baseline.missingSensitivePatterns.isEmpty)

        try FileManager.default.removeItem(at: directoryURL.appendingPathComponent(".cursorignore"))

        let result = auditor.audit(directoryURL: directoryURL)
        XCTAssertEqual(result.status, .fail)
        XCTAssertEqual(result.missingSensitivePatterns.first?.exposedRelativePaths, ["server.pem"])
    }

    func testAuditDeltaMatchesFullAuditAfterIgnoreFileAdded() throws {
        let directoryURL = try makeTemporaryDirectory()
        let baseline = auditor.audit(directoryURL: directoryURL)
        XCTAssertEqual(baseline.status, .warning)

        try writeIgnoreFile(at: ".cursorignore", in: directoryURL)

        let deltaResult = auditor.auditDelta(
            directoryURL: directoryURL,
            changedRelativePaths: [".cursorignore"],
            previousResult: baseline
        )
        let fullResult = auditor.audit(directoryURL: directoryURL)

        XCTAssertEqual(deltaResult?.status, fullResult.status)
        XCTAssertEqual(
            Set(deltaResult?.foundRelativePaths ?? []),
            Set(fullResult.foundRelativePaths)
        )
    }

    func testAuditDeltaReturnsNilForEmptyChangedPaths() throws {
        let directoryURL = try makeTemporaryDirectory()
        let baseline = auditor.audit(directoryURL: directoryURL)

        XCTAssertNil(
            auditor.auditDelta(
                directoryURL: directoryURL,
                changedRelativePaths: [],
                previousResult: baseline
            )
        )
    }

    func testAuditDeltaFallsBackToFullAuditWhenConfigurationChanges() throws {
        let directoryURL = try makeTemporaryDirectory()
        let reducedConfiguration = AIWorkspacePrivacyAuditConfiguration(
            rules: AIWorkspacePrivacyRule.defaultRules,
            sensitivePatterns: AIWorkspaceSensitivePattern.defaultPatterns.filter { $0.id != "terraform-state" }
        )
        let baseline = auditor.audit(directoryURL: directoryURL, configuration: reducedConfiguration)
        XCTAssertFalse(
            baseline.sensitivePatternFindings.contains { $0.pattern.id == "terraform-state" },
            "Reduced configuration must not include terraform-state."
        )

        let deltaResult = auditor.auditDelta(
            directoryURL: directoryURL,
            changedRelativePaths: [".cursorignore"],
            previousResult: baseline,
            configuration: .default
        )
        let fullResult = auditor.audit(directoryURL: directoryURL, configuration: .default)

        XCTAssertNotNil(deltaResult)
        XCTAssertTrue(
            deltaResult?.sensitivePatternFindings.contains { $0.pattern.id == "terraform-state" } == true,
            "A changed rule/pattern set must trigger a full re-audit using the new configuration."
        )
        XCTAssertEqual(deltaResult?.status, fullResult.status)
        XCTAssertEqual(
            Set(deltaResult?.sensitivePatternFindings.map(\.pattern.id) ?? []),
            Set(fullResult.sensitivePatternFindings.map(\.pattern.id))
        )
        XCTAssertEqual(
            Set(deltaResult?.ruleFindings.map(\.rule.id) ?? []),
            Set(fullResult.ruleFindings.map(\.rule.id))
        )
    }

    func testAuditDeltaReusesUnchangedIgnoreFileCoverage() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n*.pem\n*.key\n")
        try writeFile(".aiexclude", in: directoryURL, contents: "*.pem\n*.key\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")
        try writeFile("secret.key", in: directoryURL, contents: "key")

        let baseline = auditor.audit(directoryURL: directoryURL)
        XCTAssertFalse(baseline.missingSensitivePatterns.contains { $0.pattern.id == "pem-files" })
        XCTAssertFalse(baseline.missingSensitivePatterns.contains { $0.pattern.id == "key-files" })

        // Drop the PEM coverage from .cursorignore; .aiexclude is left untouched.
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n*.key\n")

        let deltaResult = auditor.auditDelta(
            directoryURL: directoryURL,
            changedRelativePaths: [".cursorignore"],
            previousResult: baseline
        )
        let fullResult = auditor.audit(directoryURL: directoryURL)

        XCTAssertNotNil(deltaResult)
        XCTAssertTrue(
            deltaResult?.missingSensitivePatterns.contains { $0.pattern.id == "pem-files" } == true,
            "Removing `*.pem` from the changed file must drop PEM coverage."
        )
        XCTAssertFalse(
            deltaResult?.missingSensitivePatterns.contains { $0.pattern.id == "key-files" } == true,
            "`*.key` lives in the unchanged .aiexclude and its coverage must be preserved."
        )
        XCTAssertEqual(deltaResult?.status, fullResult.status)
        XCTAssertEqual(
            Set(deltaResult?.missingSensitivePatterns.map(\.pattern.id) ?? []),
            Set(fullResult.missingSensitivePatterns.map(\.pattern.id))
        )
    }

    func testAuditDeltaDetectsNewlyExposedSensitiveFile() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")

        let baseline = auditor.audit(directoryURL: directoryURL)
        XCTAssertTrue(baseline.missingSensitivePatterns.isEmpty)

        try writeFile("server.pem", in: directoryURL, contents: "key")

        let deltaResult = auditor.auditDelta(
            directoryURL: directoryURL,
            changedRelativePaths: ["server.pem"],
            previousResult: baseline
        )
        let fullResult = auditor.audit(directoryURL: directoryURL)

        XCTAssertNotNil(deltaResult)
        XCTAssertEqual(deltaResult?.missingSensitivePatterns.map(\.pattern.id), ["pem-files"])
        XCTAssertEqual(deltaResult?.missingSensitivePatterns.first?.exposedRelativePaths, ["server.pem"])
        XCTAssertEqual(deltaResult?.status, fullResult.status)
    }

    func testAuditDeltaDetectsCursorExposureWhenOtherIgnoreFilesCoverPem() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile(".claudeignore", in: directoryURL, contents: AIWorkspacePrivacyIgnoreTemplate.contents)

        let baseline = auditor.audit(directoryURL: directoryURL)
        XCTAssertTrue(baseline.missingSensitivePatterns.isEmpty)
        XCTAssertEqual(baseline.ruleFindings.first { $0.rule.id == "cursor-ignore" }?.exposedRelativePaths, [])

        try writeFile("cert.pem", in: directoryURL, contents: "key")

        let deltaResult = auditor.auditDelta(
            directoryURL: directoryURL,
            changedRelativePaths: ["cert.pem"],
            previousResult: baseline
        )
        let fullResult = auditor.audit(directoryURL: directoryURL)

        XCTAssertNotNil(deltaResult)
        let cursorFinding = deltaResult?.ruleFindings.first { $0.rule.id == "cursor-ignore" }
        XCTAssertEqual(cursorFinding?.exposedRelativePaths, ["cert.pem"])
        XCTAssertEqual(deltaResult?.missingSensitivePatterns.first?.exposedRelativePaths, ["cert.pem"])
        XCTAssertEqual(deltaResult?.status, .fail)
        XCTAssertEqual(deltaResult?.status, fullResult.status)
    }

    func testMissingCursorIgnoreStillDetectsPemExposureWhenOtherToolsCoverIt() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".claudeignore", in: directoryURL, contents: AIWorkspacePrivacyIgnoreTemplate.contents)
        try writeFile("cert.pem", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)

        let cursorFinding = result.ruleFindings.first { $0.rule.id == "cursor-ignore" }
        XCTAssertFalse(cursorFinding?.isSatisfied ?? true)
        XCTAssertEqual(cursorFinding?.exposedRelativePaths, ["cert.pem"])
        XCTAssertEqual(result.missingSensitivePatterns.first?.exposedRelativePaths, ["cert.pem"])
        XCTAssertEqual(result.status, .fail)
    }

    func testAuditDeltaDetectsMissingCursorIgnoreExposureWhenPemAppears() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".claudeignore", in: directoryURL, contents: AIWorkspacePrivacyIgnoreTemplate.contents)

        let baseline = auditor.audit(directoryURL: directoryURL)
        XCTAssertEqual(baseline.status, .warning)

        try writeFile("cert.pem", in: directoryURL, contents: "key")

        let deltaResult = auditor.auditDelta(
            directoryURL: directoryURL,
            changedRelativePaths: ["cert.pem"],
            previousResult: baseline
        )

        XCTAssertNotNil(deltaResult)
        XCTAssertEqual(deltaResult?.ruleFindings.first { $0.rule.id == "cursor-ignore" }?.exposedRelativePaths, ["cert.pem"])
        XCTAssertEqual(deltaResult?.status, .fail)
    }

    func testAuditDeltaClearsExposedFileWhenDeleted() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let baseline = auditor.audit(directoryURL: directoryURL)
        XCTAssertEqual(baseline.missingSensitivePatterns.map(\.pattern.id), ["pem-files"])

        try FileManager.default.removeItem(at: directoryURL.appendingPathComponent("server.pem"))

        let deltaResult = auditor.auditDelta(
            directoryURL: directoryURL,
            changedRelativePaths: ["server.pem"],
            previousResult: baseline
        )
        let fullResult = auditor.audit(directoryURL: directoryURL)

        XCTAssertNotNil(deltaResult)
        XCTAssertTrue(deltaResult?.missingSensitivePatterns.isEmpty == true)
        XCTAssertEqual(deltaResult?.status, fullResult.status)
        XCTAssertEqual(deltaResult?.exposedRelativePaths, [])
    }

    func testExposedFileWhenNoIgnoreFilesExist() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertTrue(result.missingRequiredRules.contains { $0.rule.id == "cursor-ignore" })
        XCTAssertEqual(result.missingSensitivePatterns.map(\.pattern.id), ["pem-files"])
        XCTAssertEqual(result.missingSensitivePatterns.first?.exposedRelativePaths, ["server.pem"])
    }

    func testPerToolRuleExposureWhenCopilotCoversPemButCursorDoesNot() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile(".aiexclude", in: directoryURL, contents: "*.pem\n")
        try writeFile("id.pem", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)

        let cursorFinding = result.ruleFindings.first { $0.rule.id == "cursor-ignore" }
        let copilotFinding = result.ruleFindings.first { $0.rule.id == "copilot-exclude" }
        XCTAssertEqual(cursorFinding?.exposedRelativePaths, ["id.pem"])
        XCTAssertEqual(copilotFinding?.exposedRelativePaths, [])
        XCTAssertEqual(result.missingSensitivePatterns.map(\.pattern.id), ["pem-files"])
        XCTAssertEqual(result.missingSensitivePatterns.first?.exposedRelativePaths, ["id.pem"])
    }

    func testCursorExposureWhenClaudeIgnoreStillCoversPem() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile(".claudeignore", in: directoryURL, contents: AIWorkspacePrivacyIgnoreTemplate.contents)
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let result = auditor.audit(directoryURL: directoryURL)

        let cursorFinding = result.ruleFindings.first { $0.rule.id == "cursor-ignore" }
        let claudeFinding = result.ruleFindings.first { $0.rule.id == "claude-ignore" }
        XCTAssertEqual(cursorFinding?.exposedRelativePaths, ["server.pem"])
        XCTAssertEqual(claudeFinding?.exposedRelativePaths, [])
        XCTAssertEqual(result.missingSensitivePatterns.map(\.pattern.id), ["pem-files"])
        XCTAssertEqual(result.missingSensitivePatterns.first?.exposedRelativePaths, ["server.pem"])
        XCTAssertEqual(result.status, .fail)
    }

    func testAuditDeltaDetectsCursorExposureWhenPemRemovedButClaudeStillCovers() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: AIWorkspacePrivacyIgnoreTemplate.contents)
        try writeFile(".claudeignore", in: directoryURL, contents: AIWorkspacePrivacyIgnoreTemplate.contents)
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let baseline = auditor.audit(directoryURL: directoryURL)
        XCTAssertTrue(baseline.missingSensitivePatterns.isEmpty)

        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")

        let deltaResult = auditor.auditDelta(
            directoryURL: directoryURL,
            changedRelativePaths: [".cursorignore"],
            previousResult: baseline
        )
        let fullResult = auditor.audit(directoryURL: directoryURL)

        XCTAssertNotNil(deltaResult)
        XCTAssertEqual(deltaResult?.missingSensitivePatterns.map(\.pattern.id), ["pem-files"])
        XCTAssertEqual(deltaResult?.missingSensitivePatterns.first?.exposedRelativePaths, ["server.pem"])
        XCTAssertEqual(deltaResult?.status, fullResult.status)
        XCTAssertEqual(deltaResult?.status, .fail)
    }

    func testEnvExampleIsNotTreatedAsExposed() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile(".env.example", in: directoryURL, contents: "EXAMPLE=1")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertTrue(result.missingSensitivePatterns.isEmpty)
    }

    func testBootstrapAuditDetectsExposedSensitiveFiles() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")
        try writeFile("certs/prod.pem", in: directoryURL, contents: "key")
        try writeFile(".env.local", in: directoryURL, contents: "SECRET=1")

        let result = auditor.audit(directoryURL: directoryURL)

        XCTAssertEqual(result.exposedRelativePaths, ["certs/prod.pem"])
        XCTAssertEqual(result.missingSensitivePatterns.map(\.pattern.id), ["pem-files"])
    }

    func testIncompleteExposureScanAddsWarningAndError() throws {
        let directoryURL = try makeTemporaryDirectory()
        for index in 0..<5 {
            try writeFile("file\(index).pem", in: directoryURL, contents: "key")
        }

        let configuration = AIWorkspacePrivacyAuditConfiguration(
            rules: [],
            sensitivePatterns: AIWorkspaceSensitivePattern.defaultPatterns.filter { $0.id == "pem-files" },
            exposureScanLimits: SensitivePathExposureScanLimits(maxFiles: 1, timeLimit: nil)
        )

        let result = auditor.audit(directoryURL: directoryURL, configuration: configuration)

        XCTAssertEqual(result.status, .fail)
        XCTAssertTrue(result.errors.contains { $0.id == "exposure-scan-incomplete" })
        XCTAssertFalse(result.exposureScanCompletion.isComplete)
        XCTAssertFalse(result.exposureIndex?.sensitiveRelativePaths.isEmpty ?? true)
    }

    func testIgnoreChangeReevaluatesFromExposureIndex() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n*.pem\n")
        try writeFile("server.pem", in: directoryURL, contents: "key")

        let baseline = auditor.audit(
            directoryURL: directoryURL,
            configuration: AIWorkspacePrivacyAuditConfiguration(
                rules: AIWorkspacePrivacyRule.defaultRules.filter { $0.id == "cursor-ignore" },
                sensitivePatterns: AIWorkspaceSensitivePattern.defaultPatterns.filter { $0.id == "pem-files" },
                exposureScanLimits: .unlimited
            )
        )
        XCTAssertTrue(baseline.missingSensitivePatterns.isEmpty)
        XCTAssertTrue(baseline.exposureScanCompletion.isComplete)
        XCTAssertTrue(baseline.exposureIndex?.sensitiveRelativePaths.contains("server.pem") == true)

        try writeFile(".cursorignore", in: directoryURL, contents: ".env*\n")

        let deltaResult = auditor.auditDelta(
            directoryURL: directoryURL,
            changedRelativePaths: [".cursorignore"],
            previousResult: baseline,
            configuration: AIWorkspacePrivacyAuditConfiguration(
                rules: AIWorkspacePrivacyRule.defaultRules.filter { $0.id == "cursor-ignore" },
                sensitivePatterns: AIWorkspaceSensitivePattern.defaultPatterns.filter { $0.id == "pem-files" },
                exposureScanLimits: SensitivePathExposureScanLimits(maxFiles: 1, timeLimit: nil)
            )
        )
        let fullResult = auditor.audit(
            directoryURL: directoryURL,
            configuration: AIWorkspacePrivacyAuditConfiguration(
                rules: AIWorkspacePrivacyRule.defaultRules.filter { $0.id == "cursor-ignore" },
                sensitivePatterns: AIWorkspaceSensitivePattern.defaultPatterns.filter { $0.id == "pem-files" },
                exposureScanLimits: .unlimited
            )
        )

        XCTAssertNotNil(deltaResult)
        XCTAssertEqual(deltaResult?.missingSensitivePatterns.map(\.pattern.id), ["pem-files"])
        XCTAssertEqual(deltaResult?.status, fullResult.status)
        XCTAssertEqual(deltaResult?.exposureScanCompletion, .complete)
        XCTAssertEqual(deltaResult?.exposureIndex?.sensitiveRelativePaths, baseline.exposureIndex?.sensitiveRelativePaths)
    }

    func testFixerRefusesToWriteThroughSymlinkEscapingRoot() throws {
        let rootURL = try makeTemporaryDirectory().standardizedFileURL
        let outsideURL = try makeTemporaryDirectory().standardizedFileURL
        try FileManager.default.createSymbolicLink(
            at: rootURL.appendingPathComponent("escape"),
            withDestinationURL: outsideURL
        )

        let rule = AIWorkspacePrivacyRule(
            id: "escape-rule",
            toolName: "Test",
            title: "escape",
            relativePathPatterns: ["escape/secret.txt"],
            severity: .required,
            scansForSensitivePatterns: false,
            remediation: "",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: "escape/secret.txt",
                contents: "secret\n",
                strategy: .createIfMissing
            )
        )
        let configuration = AIWorkspacePrivacyAuditConfiguration(rules: [rule], sensitivePatterns: [])

        let result = auditor.audit(directoryURL: rootURL, configuration: configuration)
        XCTAssertTrue(result.missingRequiredRules.contains { $0.rule.id == "escape-rule" })

        let fixResult = fixer.fix(result: result, configuration: configuration)

        XCTAssertEqual(fixResult.errors.map(\.id), ["invalid-fix-path"])
        XCTAssertFalse(fixResult.didChangeFiles)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outsideURL.appendingPathComponent("secret.txt").path),
            "A symlinked subdirectory must not let the fixer write outside the selected directory."
        )
    }
}

private final class FixErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var results: [AIWorkspacePrivacyFixResult] = []

    func append(_ result: AIWorkspacePrivacyFixResult) {
        lock.lock()
        defer { lock.unlock() }
        results.append(result)
    }
}
