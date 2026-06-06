import AppUIKit
import Foundation
import WorkspacePolicyCore

enum DirectoryCheckPresentation {
    static func displayPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func statusTitle(for status: AIWorkspacePrivacyAuditStatus) -> String {
        switch status {
        case .pass:
            return OffsendStrings.directoryCheckStatusPass
        case .warning:
            return OffsendStrings.directoryCheckStatusWarning
        case .fail:
            return OffsendStrings.directoryCheckStatusFail
        }
    }

    static func statusBadgeStyle(for status: AIWorkspacePrivacyAuditStatus) -> OFStatusBadgeStyle {
        switch status {
        case .pass:
            return .pass
        case .warning:
            return .warn
        case .fail:
            return .fail
        }
    }

    static func displayStatusBadgeStyle(for status: DirectoryCheckDisplayStatus) -> OFStatusBadgeStyle {
        switch status {
        case .pass:
            return .pass
        case .fail:
            return .fail
        case .info:
            return .info
        }
    }

    /// UI-only status: FAIL for exposed sensitive files; INFO for missing ignore files and setup gaps.
    static func displayStatus(for result: AIWorkspacePrivacyAuditResult) -> DirectoryCheckDisplayStatus {
        if !result.errors.isEmpty { return .fail }
        if hasPatternErrors(in: result) { return .fail }
        if hasNoIgnoreFiles(in: result) { return .info }
        if !result.missingRequiredRules.isEmpty { return .info }
        if !result.missingRecommendedRules.isEmpty { return .info }
        return .pass
    }

    static func displayStatusTitle(for result: AIWorkspacePrivacyAuditResult) -> String {
        let status = displayStatus(for: result)
        switch status {
        case .info where hasNoIgnoreFiles(in: result) && !hasPatternErrors(in: result):
            return OffsendStrings.directoryCheckStatusNoIgnoreFiles
        case .info:
            return OffsendStrings.directoryCheckStatusInfo
        case .fail:
            return statusTitle(for: .fail)
        case .pass:
            return statusTitle(for: .pass)
        }
    }

    static func hasNoIgnoreFiles(in result: AIWorkspacePrivacyAuditResult) -> Bool {
        !result.ruleFindings.contains {
            $0.rule.scansForSensitivePatterns && $0.isSatisfied && !$0.matchedRelativePaths.isEmpty
        }
    }

    static func hasPatternErrors(in result: AIWorkspacePrivacyAuditResult) -> Bool {
        result.missingSensitivePatterns.contains(where: { !$0.isSatisfied })
    }

    static func satisfiedRulesForDisplay(
        in result: AIWorkspacePrivacyAuditResult
    ) -> [AIWorkspacePrivacyRuleFinding] {
        let satisfied = result.ruleFindings.filter(\.isSatisfied)
        guard !hasNoIgnoreFiles(in: result) else {
            return satisfied.filter { !$0.rule.scansForSensitivePatterns }
        }
        return satisfied
    }

    static func satisfiedPatternsForDisplay(
        in result: AIWorkspacePrivacyAuditResult
    ) -> [AIWorkspaceSensitivePatternFinding] {
        guard !hasNoIgnoreFiles(in: result) else { return [] }
        return result.sensitivePatternFindings.filter(\.isSatisfied)
    }

    static func hasSatisfiedFindings(in result: AIWorkspacePrivacyAuditResult) -> Bool {
        !satisfiedRulesForDisplay(in: result).isEmpty
            || !satisfiedPatternsForDisplay(in: result).isEmpty
    }

    static func severityTag(_ severity: AIWorkspacePrivacyRuleSeverity) -> DirectoryCheckFindingTag {
        switch severity {
        case .required:
            return .fail
        case .recommended:
            return .warn
        case .informational:
            return .info
        }
    }

    static func issueCounts(for result: AIWorkspacePrivacyAuditResult) -> DirectoryCheckIssueCounts {
        let fail = result.errors.count
            + result.missingSensitivePatterns.filter { !$0.isSatisfied }.count
        let info = result.missingRequiredRules.count + result.missingRecommendedRules.count
        let ok = satisfiedRulesForDisplay(in: result).count
            + satisfiedPatternsForDisplay(in: result).count
        return DirectoryCheckIssueCounts(fail: fail, info: info, ok: ok)
    }

    static func issueSummaryTitle(for counts: DirectoryCheckIssueCounts) -> String {
        if counts.fail > 0 {
            return OffsendStrings.directoryCheckIssuesFound(counts.fail)
        }
        if counts.info > 0 {
            return OffsendStrings.directoryCheckSetupItemsFound(counts.info)
        }
        if counts.ok > 0 {
            return OffsendStrings.directoryCheckAllChecksPassed
        }
        return OffsendStrings.directoryCheckIssuesFound(0)
    }

    static func satisfiedRuleSubtitle(for finding: AIWorkspacePrivacyRuleFinding) -> String {
        guard !finding.matchedRelativePaths.isEmpty else {
            return finding.rule.remediation
        }
        return OffsendStrings.directoryCheckSatisfiedFound(finding.matchedRelativePaths.joined(separator: ", "))
    }

    static func satisfiedPatternSubtitle(for finding: AIWorkspaceSensitivePatternFinding) -> String {
        guard !finding.matchedIgnoreFilePaths.isEmpty else {
            return OffsendStrings.directoryCheckSatisfiedPatternCovered
        }
        return OffsendStrings.directoryCheckSatisfiedPatternIgnoreFiles(
            finding.matchedIgnoreFilePaths.joined(separator: ", ")
        )
    }

    static func ruleFindingSubtitle(for finding: AIWorkspacePrivacyRuleFinding) -> String {
        guard !finding.exposedRelativePaths.isEmpty else {
            return finding.rule.remediation
        }
        return OffsendStrings.directoryCheckRuleExposedFiles(
            finding.rule.toolName,
            finding.exposedRelativePaths.joined(separator: ", ")
        )
    }

    static func sensitivePatternSubtitle(for finding: AIWorkspaceSensitivePatternFinding) -> String {
        guard !finding.exposedRelativePaths.isEmpty else {
            return finding.pattern.remediation
        }
        return OffsendStrings.directoryCheckExposedFiles(finding.exposedRelativePaths.joined(separator: ", "))
    }

    static func fixItemSubtitle(for item: AIWorkspacePrivacyFixItem) -> String {
        switch item.kind {
        case let .ruleFile(relativePath, strategy):
            switch strategy {
            case .createIfMissing:
                return OffsendStrings.directoryCheckFixSelectionRuleCreate(relativePath)
            case .mergeLines:
                return OffsendStrings.directoryCheckFixSelectionRuleUpdate(relativePath)
            }
        case let .sensitivePattern(canonicalLine):
            return OffsendStrings.directoryCheckFixSelectionPatternAdd(canonicalLine)
        }
    }

    static func fixResultMessage(_ result: AIWorkspacePrivacyFixResult) -> String {
        var parts: [String] = []
        if result.didChangeFiles {
            parts.append(fixSummary(result))
        } else if result.errors.isEmpty {
            return OffsendStrings.directoryCheckFixNoChanges
        }
        if !result.errors.isEmpty {
            parts.append(
                OffsendStrings.directoryCheckFixErrors(
                    result.errors.map(\.message).joined(separator: "\n")
                )
            )
        }
        return parts.joined(separator: "\n\n")
    }

    static func fixSummary(_ result: AIWorkspacePrivacyFixResult) -> String {
        if !result.didChangeFiles {
            return OffsendStrings.directoryCheckFixNoChanges
        }

        var parts: [String] = []
        if !result.createdRelativePaths.isEmpty {
            parts.append(OffsendStrings.directoryCheckFixCreated(result.createdRelativePaths.joined(separator: ", ")))
        }
        if !result.updatedRelativePaths.isEmpty {
            parts.append(OffsendStrings.directoryCheckFixUpdated(result.updatedRelativePaths.joined(separator: ", ")))
        }
        return parts.joined(separator: "\n")
    }

    static func fixFooterStatusText(for summary: DirectoryCheckFixApplySummary) -> String {
        guard summary.fileCount > 0 else {
            return OffsendStrings.directoryCheckFixSelectionNoneSelected
        }
        if summary.createsNewFilesOnly {
            return OffsendStrings.directoryCheckFixesCreateFiles(summary.fileCount)
        }
        if summary.patternFixCount > 0 {
            return OffsendStrings.directoryCheckFixesPatternsInFiles(
                summary.patternFixCount,
                summary.fileCount
            )
        }
        return OffsendStrings.directoryCheckFixesFilesSelected(summary.fileCount)
    }

    static func applyButtonTitle(for summary: DirectoryCheckFixApplySummary) -> String {
        guard summary.fileCount > 0 else {
            return OffsendStrings.directoryCheckApply
        }
        if summary.createsNewFilesOnly {
            return OffsendStrings.directoryCheckApply
        }

        let fixes = max(summary.patternFixCount, summary.updatesExistingFiles ? 1 : 0)
        let files = summary.fileCount

        if fixes == 0 {
            return OffsendStrings.directoryCheckApply
        }

        if fixes == 1, files == 1 {
            return OffsendStrings.directoryCheckApplyFixToOneFile
        }
        if fixes == 1 {
            return OffsendStrings.directoryCheckApplyFixToFiles(files)
        }
        if files == 1 {
            return OffsendStrings.directoryCheckApplyFixesToOneFile(fixes)
        }
        return OffsendStrings.directoryCheckApplyFixesToFiles(fixes, files)
    }
}
