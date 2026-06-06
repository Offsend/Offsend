import XCTest
@testable import WorkspacePolicyCore

final class DirectoryCheckConfigurationResolverTests: XCTestCase {
    func testFreeAndProUseIdenticalDetectionScope() {
        let freeConfig = DirectoryCheckConfigurationResolver.resolve(
            DirectoryCheckConfigurationInput(
                workspaceAuditFull: false,
                disabledRuleIDs: [],
                extraSkippedDirectories: [],
                customIgnoreTemplate: nil
            )
        )
        let proConfig = DirectoryCheckConfigurationResolver.resolve(
            DirectoryCheckConfigurationInput(
                workspaceAuditFull: true,
                disabledRuleIDs: [],
                extraSkippedDirectories: [],
                customIgnoreTemplate: nil
            )
        )

        XCTAssertEqual(freeConfig.rules.count, AIWorkspacePrivacyRule.defaultRules.count)
        XCTAssertEqual(freeConfig.sensitivePatterns.count, AIWorkspaceSensitivePattern.defaultPatterns.count)
        XCTAssertEqual(Set(freeConfig.rules.map(\.id)), Set(proConfig.rules.map(\.id)))
        XCTAssertEqual(Set(freeConfig.sensitivePatterns.map(\.id)), Set(proConfig.sensitivePatterns.map(\.id)))
    }

    func testCustomTemplateIgnoredOnFreeTier() {
        let config = DirectoryCheckConfigurationResolver.resolve(
            DirectoryCheckConfigurationInput(
                workspaceAuditFull: false,
                disabledRuleIDs: [],
                extraSkippedDirectories: [],
                customIgnoreTemplate: "# custom\nsecret/"
            )
        )

        let cursorFix = config.rules.first { $0.id == "cursor-ignore" }?.fix
        XCTAssertEqual(cursorFix?.contents, AIWorkspacePrivacyIgnoreTemplate.contents)
    }

    func testDisabledRecommendedRulesAreExcluded() {
        let disabled: Set<String> = ["copilot-exclude"]
        let config = DirectoryCheckConfigurationResolver.resolve(
            DirectoryCheckConfigurationInput(
                workspaceAuditFull: true,
                disabledRuleIDs: disabled,
                extraSkippedDirectories: [],
                customIgnoreTemplate: nil
            )
        )

        XCTAssertFalse(config.rules.contains(where: { $0.id == "copilot-exclude" }))
        XCTAssertTrue(config.rules.contains(where: { $0.id == "cursor-ignore" }))
    }

    func testCustomTemplateAppliedToFixableRules() {
        let template = "# custom\nsecret/"
        let config = DirectoryCheckConfigurationResolver.resolve(
            DirectoryCheckConfigurationInput(
                workspaceAuditFull: true,
                disabledRuleIDs: [],
                extraSkippedDirectories: [],
                customIgnoreTemplate: template
            )
        )

        let cursorRule = config.rules.first(where: { $0.id == "cursor-ignore" })
        XCTAssertEqual(cursorRule?.fix?.contents, template)
    }

    func testExtraSkippedDirectoriesMerged() {
        let config = DirectoryCheckConfigurationResolver.resolve(
            DirectoryCheckConfigurationInput(
                workspaceAuditFull: true,
                disabledRuleIDs: [],
                extraSkippedDirectories: ["  vendor  ", ""],
                customIgnoreTemplate: nil
            )
        )

        XCTAssertTrue(config.additionalSkippedDirectoryNames.contains("vendor"))
        XCTAssertEqual(config.additionalSkippedDirectoryNames.count, 1)
    }
}

final class WorkspaceWatchStatusDegradeTests: XCTestCase {
    func testDetectsPassToWarningDegrade() {
        XCTAssertTrue(WorkspaceWatchStatusDegrade.didDegrade(from: .pass, to: .warning))
    }

    func testDetectsWarningToFailDegrade() {
        XCTAssertTrue(WorkspaceWatchStatusDegrade.didDegrade(from: .warning, to: .fail))
    }

    func testIgnoresImprovement() {
        XCTAssertFalse(WorkspaceWatchStatusDegrade.didDegrade(from: .fail, to: .pass))
    }

    func testCountsOnlyFailAsAttention() {
        XCTAssertTrue(WorkspaceWatchStatusDegrade.countsAsAttention(.fail))
        XCTAssertFalse(WorkspaceWatchStatusDegrade.countsAsAttention(.warning))
        XCTAssertFalse(WorkspaceWatchStatusDegrade.countsAsAttention(.pass))
    }

    func testFreeTierNotifiesOnlyOnFail() {
        XCTAssertTrue(
            WorkspaceWatchStatusDegrade.shouldNotify(
                from: .pass,
                to: .fail,
                workspaceAuditFull: false
            )
        )
        XCTAssertFalse(
            WorkspaceWatchStatusDegrade.shouldNotify(
                from: .pass,
                to: .warning,
                workspaceAuditFull: false
            )
        )
    }

    func testProTierNotifiesOnWarning() {
        XCTAssertTrue(
            WorkspaceWatchStatusDegrade.shouldNotify(
                from: .pass,
                to: .warning,
                workspaceAuditFull: true
            )
        )
    }

    func testWorstStatusPicksFail() {
        XCTAssertEqual(
            WorkspaceWatchStatusDegrade.worstStatus(in: [.pass, .warning, .fail]),
            .fail
        )
    }

    func testSameStatusIsNotDegrade() {
        XCTAssertFalse(WorkspaceWatchStatusDegrade.didDegrade(from: .fail, to: .fail))
        XCTAssertFalse(WorkspaceWatchStatusDegrade.didDegrade(from: .warning, to: .warning))
    }

    func testFirstAuditNeverNotifies() {
        XCTAssertFalse(
            WorkspaceWatchStatusDegrade.shouldNotify(
                from: nil,
                to: .fail,
                workspaceAuditFull: true
            )
        )
    }

    func testNotifiesWhenNewSensitivePathsAppearEvenIfStatusStaysFail() {
        XCTAssertTrue(
            WorkspaceWatchStatusDegrade.shouldNotify(
                from: .fail,
                to: .fail,
                workspaceAuditFull: false,
                addedExposedRelativePaths: ["cert.pem"]
            )
        )
    }

    func testFreeTierIgnoresNewExposureWhenStatusIsNotFail() {
        XCTAssertFalse(
            WorkspaceWatchStatusDegrade.shouldNotify(
                from: .pass,
                to: .warning,
                workspaceAuditFull: false,
                addedExposedRelativePaths: ["cert.pem"]
            )
        )
    }

    func testWorstStatusReturnsNilForEmptyList() {
        XCTAssertNil(WorkspaceWatchStatusDegrade.worstStatus(in: []))
    }

    func testWorstStatusWithSingleElementReturnsThatElement() {
        XCTAssertEqual(WorkspaceWatchStatusDegrade.worstStatus(in: [.warning]), .warning)
    }
}

final class WorkspaceWatchNotificationFormatterTests: XCTestCase {
    func testFormatsSingleExposedPath() {
        let pattern = AIWorkspaceSensitivePattern(
            id: "pem-files",
            title: "PEM",
            acceptedPatterns: ["*.pem"],
            remediation: ""
        )
        let result = AIWorkspacePrivacyAuditResult(
            directoryURL: URL(fileURLWithPath: "/tmp/project"),
            status: .fail,
            ruleFindings: [],
            sensitivePatternFindings: [
                AIWorkspaceSensitivePatternFinding(
                    pattern: pattern,
                    matchedIgnoreFilePaths: [],
                    exposedRelativePaths: ["server.pem"]
                )
            ],
            errors: []
        )

        XCTAssertEqual(
            WorkspaceWatchNotificationFormatter.exposedPathsSummary(from: result),
            "server.pem"
        )
    }

    func testTruncatesWithMoreSuffix() {
        let pattern = AIWorkspaceSensitivePattern(
            id: "pem-files",
            title: "PEM",
            acceptedPatterns: ["*.pem"],
            remediation: ""
        )
        let result = AIWorkspacePrivacyAuditResult(
            directoryURL: URL(fileURLWithPath: "/tmp/project"),
            status: .fail,
            ruleFindings: [],
            sensitivePatternFindings: [
                AIWorkspaceSensitivePatternFinding(
                    pattern: pattern,
                    matchedIgnoreFilePaths: [],
                    exposedRelativePaths: ["a.pem", "b.pem", "c.pem"]
                )
            ],
            errors: []
        )

        XCTAssertEqual(
            WorkspaceWatchNotificationFormatter.exposedPathsSummary(from: result, limit: 2),
            "a.pem, b.pem +1 more"
        )
    }

    func testDeltaSummaryUsesNewlyExposedPaths() {
        let pattern = AIWorkspaceSensitivePattern(
            id: "pem-files",
            title: "PEM",
            acceptedPatterns: ["*.pem"],
            remediation: ""
        )
        let previous = AIWorkspacePrivacyAuditResult(
            directoryURL: URL(fileURLWithPath: "/tmp/project"),
            status: .pass,
            ruleFindings: [],
            sensitivePatternFindings: [
                AIWorkspaceSensitivePatternFinding(
                    pattern: pattern,
                    matchedIgnoreFilePaths: [".cursorignore"],
                    exposedRelativePaths: []
                )
            ],
            errors: []
        )
        let current = AIWorkspacePrivacyAuditResult(
            directoryURL: URL(fileURLWithPath: "/tmp/project"),
            status: .fail,
            ruleFindings: [],
            sensitivePatternFindings: [
                AIWorkspaceSensitivePatternFinding(
                    pattern: pattern,
                    matchedIgnoreFilePaths: [".cursorignore"],
                    exposedRelativePaths: ["server.pem"]
                )
            ],
            errors: []
        )
        let delta = AIWorkspacePrivacyAuditDelta.compute(from: previous, to: current)

        XCTAssertEqual(
            WorkspaceWatchNotificationFormatter.exposedPathsSummary(from: delta),
            "server.pem"
        )
    }

    func testReturnsNilWhenNothingExposed() {
        let result = AIWorkspacePrivacyAuditResult(
            directoryURL: URL(fileURLWithPath: "/tmp/project"),
            status: .pass,
            ruleFindings: [],
            sensitivePatternFindings: [],
            errors: []
        )

        XCTAssertNil(WorkspaceWatchNotificationFormatter.exposedPathsSummary(from: result))
    }
}

final class WorkspaceWatchRelevantPathFilterTests: XCTestCase {
    func testFiltersIrrelevantPaths() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let config = AIWorkspacePrivacyAuditConfiguration.default

        let relevant = WorkspaceWatchRelevantPathFilter.relevantChangedPaths(
            absolutePaths: [
                "/tmp/project/README.md",
                "/tmp/project/.cursorignore",
                "/tmp/other/.cursorignore"
            ],
            rootURL: root,
            configuration: config
        )

        XCTAssertEqual(relevant, [".cursorignore"])
    }

    func testIncludesCursorRulesDirectoryChanges() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let config = AIWorkspacePrivacyAuditConfiguration.default

        let relevant = WorkspaceWatchRelevantPathFilter.relevantChangedPaths(
            absolutePaths: ["/tmp/project/.cursor/rules/privacy.mdc"],
            rootURL: root,
            configuration: config
        )

        XCTAssertTrue(relevant.contains(".cursor/rules/privacy.mdc"))
    }

    func testRootDirectoryChangeCountsAsRelevant() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let config = AIWorkspacePrivacyAuditConfiguration.default

        let relevant = WorkspaceWatchRelevantPathFilter.relevantChangedPaths(
            absolutePaths: ["/tmp/project"],
            rootURL: root,
            configuration: config
        )

        XCTAssertTrue(relevant.contains(""), "A change to the watched root itself must trigger a re-audit.")
    }

    func testIgnoresEverythingWhenNoRuleMatches() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let config = AIWorkspacePrivacyAuditConfiguration(
            rules: [
                AIWorkspacePrivacyRule(
                    id: "only-cursorignore",
                    toolName: "Cursor",
                    title: ".cursorignore",
                    relativePathPatterns: [".cursorignore"],
                    severity: .required,
                    scansForSensitivePatterns: true,
                    remediation: ""
                )
            ],
            sensitivePatterns: []
        )

        let relevant = WorkspaceWatchRelevantPathFilter.relevantChangedPaths(
            absolutePaths: ["/tmp/project/src/main.swift", "/tmp/project/README.md"],
            rootURL: root,
            configuration: config
        )

        XCTAssertTrue(relevant.isEmpty)
    }

    func testIncludesSensitiveFileChanges() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let config = AIWorkspacePrivacyAuditConfiguration.default

        let relevant = WorkspaceWatchRelevantPathFilter.relevantChangedPaths(
            absolutePaths: ["/tmp/project/certs/server.pem"],
            rootURL: root,
            configuration: config
        )

        XCTAssertEqual(relevant, ["certs/server.pem"])
    }

    func testIgnoresSensitiveFilesUnderSkippedDirectories() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let config = AIWorkspacePrivacyAuditConfiguration.default

        let relevant = WorkspaceWatchRelevantPathFilter.relevantChangedPaths(
            absolutePaths: ["/tmp/project/node_modules/secret.pem"],
            rootURL: root,
            configuration: config
        )

        XCTAssertTrue(relevant.isEmpty)
    }
}

final class AIWorkspacePrivacyAuditDeltaTests: XCTestCase {
    func testDetectsStatusAndRuleChanges() {
        let directoryURL = URL(fileURLWithPath: "/tmp/project")
        let rule = AIWorkspacePrivacyAuditConfiguration.default.rules.first { $0.id == "cursor-ignore" }!
        let previous = AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: .pass,
            ruleFindings: [
                AIWorkspacePrivacyRuleFinding(rule: rule, matchedRelativePaths: [".cursorignore"])
            ],
            sensitivePatternFindings: [],
            errors: []
        )
        let current = AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: .fail,
            ruleFindings: [
                AIWorkspacePrivacyRuleFinding(rule: rule, matchedRelativePaths: [])
            ],
            sensitivePatternFindings: [],
            errors: []
        )

        let delta = AIWorkspacePrivacyAuditDelta.compute(from: previous, to: current)

        XCTAssertTrue(delta.hasChanges)
        XCTAssertEqual(delta.previousStatus, .pass)
        XCTAssertEqual(delta.currentStatus, .fail)
        XCTAssertEqual(delta.newlyMissingRules.map(\.rule.id), ["cursor-ignore"])
        XCTAssertEqual(delta.removedMatchedPaths, [".cursorignore"])
    }

    func testDetectsNewlySatisfiedRulesAndAddedPaths() {
        let directoryURL = URL(fileURLWithPath: "/tmp/project")
        let rule = AIWorkspacePrivacyAuditConfiguration.default.rules.first { $0.id == "cursor-ignore" }!
        let previous = AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: .fail,
            ruleFindings: [AIWorkspacePrivacyRuleFinding(rule: rule, matchedRelativePaths: [])],
            sensitivePatternFindings: [],
            errors: []
        )
        let current = AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: .warning,
            ruleFindings: [AIWorkspacePrivacyRuleFinding(rule: rule, matchedRelativePaths: [".cursorignore"])],
            sensitivePatternFindings: [],
            errors: []
        )

        let delta = AIWorkspacePrivacyAuditDelta.compute(from: previous, to: current)

        XCTAssertTrue(delta.hasChanges)
        XCTAssertEqual(delta.newlySatisfiedRules.map(\.rule.id), ["cursor-ignore"])
        XCTAssertTrue(delta.newlyMissingRules.isEmpty)
        XCTAssertEqual(delta.addedMatchedPaths, [".cursorignore"])
        XCTAssertTrue(delta.removedMatchedPaths.isEmpty)
    }

    func testDetectsSensitivePatternTransitions() {
        let directoryURL = URL(fileURLWithPath: "/tmp/project")
        let pattern = AIWorkspaceSensitivePattern(
            id: "pem-files",
            title: "PEM",
            acceptedPatterns: ["*.pem"],
            remediation: ""
        )
        let previous = AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: .pass,
            ruleFindings: [],
            sensitivePatternFindings: [
                AIWorkspaceSensitivePatternFinding(
                    pattern: pattern,
                    matchedIgnoreFilePaths: [".cursorignore"],
                    exposedRelativePaths: []
                )
            ],
            errors: []
        )
        let current = AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: .fail,
            ruleFindings: [],
            sensitivePatternFindings: [
                AIWorkspaceSensitivePatternFinding(
                    pattern: pattern,
                    matchedIgnoreFilePaths: [".cursorignore"],
                    exposedRelativePaths: ["server.pem"]
                )
            ],
            errors: []
        )

        let delta = AIWorkspacePrivacyAuditDelta.compute(from: previous, to: current)

        XCTAssertEqual(delta.newlyMissingPatterns.map(\.pattern.id), ["pem-files"])
        XCTAssertTrue(delta.newlySatisfiedPatterns.isEmpty)

        let reverseDelta = AIWorkspacePrivacyAuditDelta.compute(from: current, to: previous)
        XCTAssertEqual(reverseDelta.newlySatisfiedPatterns.map(\.pattern.id), ["pem-files"])
        XCTAssertTrue(reverseDelta.newlyMissingPatterns.isEmpty)
    }

    func testIdenticalResultsHaveNoChanges() {
        let directoryURL = URL(fileURLWithPath: "/tmp/project")
        let rule = AIWorkspacePrivacyAuditConfiguration.default.rules.first { $0.id == "cursor-ignore" }!
        let result = AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: .warning,
            ruleFindings: [AIWorkspacePrivacyRuleFinding(rule: rule, matchedRelativePaths: [".cursorignore"])],
            sensitivePatternFindings: [],
            errors: []
        )

        let delta = AIWorkspacePrivacyAuditDelta.compute(from: result, to: result)

        XCTAssertFalse(delta.hasChanges)
        XCTAssertTrue(delta.addedMatchedPaths.isEmpty)
        XCTAssertTrue(delta.removedMatchedPaths.isEmpty)
    }

    func testDetectsAddedAndRemovedExposedPaths() {
        let directoryURL = URL(fileURLWithPath: "/tmp/project")
        let pattern = AIWorkspaceSensitivePattern(
            id: "pem-files",
            title: "PEM",
            acceptedPatterns: ["*.pem"],
            remediation: ""
        )
        let previous = AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: .pass,
            ruleFindings: [],
            sensitivePatternFindings: [
                AIWorkspaceSensitivePatternFinding(
                    pattern: pattern,
                    matchedIgnoreFilePaths: [],
                    exposedRelativePaths: ["a.pem"]
                )
            ],
            errors: []
        )
        let current = AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: .fail,
            ruleFindings: [],
            sensitivePatternFindings: [
                AIWorkspaceSensitivePatternFinding(
                    pattern: pattern,
                    matchedIgnoreFilePaths: [],
                    exposedRelativePaths: ["b.pem"]
                )
            ],
            errors: []
        )

        let delta = AIWorkspacePrivacyAuditDelta.compute(from: previous, to: current)

        XCTAssertEqual(delta.addedExposedRelativePaths, ["b.pem"])
        XCTAssertEqual(delta.removedExposedRelativePaths, ["a.pem"])
    }
}
