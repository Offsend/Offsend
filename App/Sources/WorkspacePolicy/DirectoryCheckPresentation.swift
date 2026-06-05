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
        let fail = result.missingRequiredRules.count
            + result.errors.count
            + result.missingSensitivePatterns.filter { $0.pattern.severity == .required }.count
        let warn = result.missingRecommendedRules.count
            + result.missingSensitivePatterns.filter { $0.pattern.severity != .required }.count
        let ok = result.ruleFindings.filter(\.isSatisfied).count
            + result.sensitivePatternFindings.filter(\.isSatisfied).count
        return DirectoryCheckIssueCounts(fail: fail, warn: warn, ok: ok)
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
}
