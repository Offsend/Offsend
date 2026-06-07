import Foundation

public struct AIWorkspacePrivacyFixItem: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case ruleFile(relativePath: String, strategy: AIWorkspacePrivacyFileFixStrategy)
        case sensitivePattern(canonicalLine: String)
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let toolName: String?
    public let severity: AIWorkspacePrivacyRuleSeverity

    public init(
        id: String,
        kind: Kind,
        title: String,
        toolName: String? = nil,
        severity: AIWorkspacePrivacyRuleSeverity
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.toolName = toolName
        self.severity = severity
    }
}

public struct AIWorkspacePrivacyFixSelection: Equatable, Sendable {
    public var ruleIDs: Set<String>
    public var patternIDs: Set<String>

    public init(ruleIDs: Set<String> = [], patternIDs: Set<String> = []) {
        self.ruleIDs = ruleIDs
        self.patternIDs = patternIDs
    }

    public var isEmpty: Bool {
        ruleIDs.isEmpty && patternIDs.isEmpty
    }
}

public enum AIWorkspacePrivacyFixPlanner {
    public static func fixScenario(for result: AIWorkspacePrivacyAuditResult) -> AIWorkspacePrivacyFixScenario {
        let hasExisting = result.ruleFindings.contains {
            $0.rule.scansForSensitivePatterns && $0.isSatisfied && !$0.matchedRelativePaths.isEmpty
        }
        return hasExisting ? .existingPolicyFiles : .noPolicyFiles
    }

    public static func isExposureGapRuleItem(
        _ item: AIWorkspacePrivacyFixItem,
        in result: AIWorkspacePrivacyAuditResult
    ) -> Bool {
        guard case .ruleFile(_, let strategy) = item.kind, strategy == .mergeLines else { return false }
        return isExposureGapPolicyTarget(itemID: item.id, in: result)
    }

    public static func isMissingRuleItem(
        _ item: AIWorkspacePrivacyFixItem,
        in result: AIWorkspacePrivacyAuditResult
    ) -> Bool {
        guard case .ruleFile = item.kind else { return false }
        guard let finding = result.ruleFindings.first(where: { $0.rule.id == item.id }) else { return false }
        return !finding.isSatisfied
    }

    public static func exposureGapRuleItems(
        from items: [AIWorkspacePrivacyFixItem],
        result: AIWorkspacePrivacyAuditResult
    ) -> [AIWorkspacePrivacyFixItem] {
        items.filter { isExposureGapRuleItem($0, in: result) }
    }

    public static func missingRuleItems(
        from items: [AIWorkspacePrivacyFixItem],
        result: AIWorkspacePrivacyAuditResult
    ) -> [AIWorkspacePrivacyFixItem] {
        items.filter { isMissingRuleItem($0, in: result) }
    }

    /// Missing policy ignore files for other AI tools (`.claudeignore`, `.aiexclude`, …).
    public static func missingIgnoreFileItems(
        for result: AIWorkspacePrivacyAuditResult,
        configuration: AIWorkspacePrivacyAuditConfiguration
    ) -> [AIWorkspacePrivacyFixItem] {
        let rulesByID = Dictionary(uniqueKeysWithValues: configuration.rules.map { ($0.id, $0) })
        var items: [AIWorkspacePrivacyFixItem] = []

        for finding in result.ruleFindings {
            let rule = finding.rule
            guard !finding.isSatisfied else { continue }
            guard rule.scansForSensitivePatterns else { continue }
            guard rule.severity != .informational else { continue }
            guard let fix = rulesByID[rule.id]?.fix ?? rule.fix else { continue }
            items.append(
                AIWorkspacePrivacyFixItem(
                    id: rule.id,
                    kind: .ruleFile(relativePath: fix.relativePath, strategy: fix.strategy),
                    title: rule.title,
                    toolName: rule.toolName,
                    severity: rule.severity
                )
            )
        }

        return items.sorted(by: sortFixItems)
    }

    public static func fixItems(
        for result: AIWorkspacePrivacyAuditResult,
        configuration: AIWorkspacePrivacyAuditConfiguration
    ) -> [AIWorkspacePrivacyFixItem] {
        var items: [AIWorkspacePrivacyFixItem] = []
        let rulesByID = Dictionary(uniqueKeysWithValues: configuration.rules.map { ($0.id, $0) })
        var addedRuleIDs = Set<String>()

        for finding in result.ruleFindings where !finding.isSatisfied && finding.rule.severity != .informational {
            let rule = finding.rule
            guard let fix = rulesByID[rule.id]?.fix ?? rule.fix else { continue }
            items.append(
                AIWorkspacePrivacyFixItem(
                    id: rule.id,
                    kind: .ruleFile(relativePath: fix.relativePath, strategy: fix.strategy),
                    title: rule.title,
                    toolName: rule.toolName,
                    severity: rule.severity
                )
            )
            addedRuleIDs.insert(rule.id)
        }

        for finding in result.ruleFindings where finding.isSatisfied
            && finding.rule.scansForSensitivePatterns
            && !finding.matchedRelativePaths.isEmpty
            && !finding.exposedRelativePaths.isEmpty
            && finding.rule.severity != .informational {
            guard !addedRuleIDs.contains(finding.rule.id) else { continue }
            guard let fix = rulesByID[finding.rule.id]?.fix ?? finding.rule.fix else { continue }
            items.append(
                AIWorkspacePrivacyFixItem(
                    id: finding.rule.id,
                    kind: .ruleFile(relativePath: fix.relativePath, strategy: .mergeLines),
                    title: finding.rule.title,
                    toolName: finding.rule.toolName,
                    severity: .recommended
                )
            )
            addedRuleIDs.insert(finding.rule.id)
        }

        for finding in result.missingSensitivePatterns {
            items.append(
                AIWorkspacePrivacyFixItem(
                    id: finding.pattern.id,
                    kind: .sensitivePattern(canonicalLine: finding.pattern.canonicalIgnoreLine),
                    title: finding.pattern.title,
                    severity: finding.pattern.severity
                )
            )
        }

        return items.sorted(by: sortFixItems)
    }

    private static func sortFixItems(_ lhs: AIWorkspacePrivacyFixItem, _ rhs: AIWorkspacePrivacyFixItem) -> Bool {
        let lhsRank = severityRank(lhs.severity)
        let rhsRank = severityRank(rhs.severity)
        if lhsRank != rhsRank { return lhsRank < rhsRank }

        switch (lhs.kind, rhs.kind) {
        case (.sensitivePattern, .ruleFile):
            return true
        case (.ruleFile, .sensitivePattern):
            return false
        default:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func severityRank(_ severity: AIWorkspacePrivacyRuleSeverity) -> Int {
        switch severity {
        case .required:
            return 0
        case .recommended:
            return 1
        case .informational:
            return 2
        }
    }

    public static func defaultSelection(
        for items: [AIWorkspacePrivacyFixItem],
        result: AIWorkspacePrivacyAuditResult
    ) -> AIWorkspacePrivacyFixSelection {
        var selection = AIWorkspacePrivacyFixSelection()
        let patternItems = items.filter {
            if case .sensitivePattern = $0.kind { return true }
            return false
        }

        for item in patternItems {
            selection.patternIDs.insert(item.id)
        }

        if patternItems.isEmpty {
            for item in items {
                if case .ruleFile = item.kind {
                    selection.ruleIDs.insert(item.id)
                }
            }
            return selection
        }

        for item in items {
            guard case .ruleFile = item.kind else { continue }
            if item.severity == .required || isExposureGapPolicyTarget(itemID: item.id, in: result) {
                selection.ruleIDs.insert(item.id)
            }
        }

        if selection.ruleIDs.isEmpty {
            for item in items {
                if case .ruleFile = item.kind {
                    selection.ruleIDs.insert(item.id)
                }
            }
        }

        return selection
    }

    private static func isExposureGapPolicyTarget(
        itemID: String,
        in result: AIWorkspacePrivacyAuditResult
    ) -> Bool {
        guard let finding = result.ruleFindings.first(where: { $0.rule.id == itemID }) else {
            return false
        }
        return finding.isSatisfied
            && finding.rule.scansForSensitivePatterns
            && !finding.exposedRelativePaths.isEmpty
    }

    public static func selection(from selectedItemIDs: Set<String>, in items: [AIWorkspacePrivacyFixItem]) -> AIWorkspacePrivacyFixSelection {
        var selection = AIWorkspacePrivacyFixSelection()
        for item in items where selectedItemIDs.contains(item.id) {
            switch item.kind {
            case .ruleFile:
                selection.ruleIDs.insert(item.id)
            case .sensitivePattern:
                selection.patternIDs.insert(item.id)
            }
        }
        return selection
    }

    public static func plannedRelativePaths(
        for result: AIWorkspacePrivacyAuditResult,
        configuration: AIWorkspacePrivacyAuditConfiguration,
        selection: AIWorkspacePrivacyFixSelection,
        createdRelativePaths: Set<String> = []
    ) -> [String] {
        var paths = Set<String>()
        let rulesByID = Dictionary(uniqueKeysWithValues: configuration.rules.map { ($0.id, $0) })

        for finding in result.ruleFindings where !finding.isSatisfied && finding.rule.severity != .informational {
            guard selection.ruleIDs.contains(finding.rule.id) else { continue }
            if let fix = rulesByID[finding.rule.id]?.fix ?? finding.rule.fix {
                paths.insert(fix.relativePath)
            }
        }

        if !selection.patternIDs.isEmpty {
            paths.formUnion(
                patternTargetRelativePaths(
                    for: result,
                    configuration: configuration,
                    selection: selection,
                    createdRelativePaths: createdRelativePaths
                )
            )
        }

        return paths.sorted()
    }

    /// Ignore files that should receive selected sensitive patterns.
    /// With a selective fix, patterns are written only into policy files chosen in `selection.ruleIDs`.
    public static func patternTargetRelativePaths(
        for result: AIWorkspacePrivacyAuditResult,
        configuration: AIWorkspacePrivacyAuditConfiguration,
        selection: AIWorkspacePrivacyFixSelection?,
        createdRelativePaths: Set<String> = []
    ) -> [String] {
        var paths = Set<String>()

        if let selection {
            let selectedScanRules = configuration.rules.filter {
                $0.scansForSensitivePatterns && selection.ruleIDs.contains($0.id)
            }
            for rule in selectedScanRules {
                if let fixPath = rule.fix?.relativePath {
                    paths.insert(fixPath)
                }
            }
            for finding in result.ruleFindings where finding.rule.scansForSensitivePatterns && selection.ruleIDs.contains(finding.rule.id) {
                paths.formUnion(finding.matchedRelativePaths)
            }
            paths.formUnion(
                createdRelativePaths.filter { path in
                    selectedScanRules.contains { $0.fix?.relativePath == path }
                }
            )
            return paths.sorted()
        }

        for finding in result.ruleFindings where finding.rule.scansForSensitivePatterns {
            paths.formUnion(finding.matchedRelativePaths)
            if let fixPath = finding.rule.fix?.relativePath {
                paths.insert(fixPath)
            }
        }
        for rule in configuration.rules where rule.scansForSensitivePatterns {
            if let fixPath = rule.fix?.relativePath {
                paths.insert(fixPath)
            }
        }
        paths.formUnion(
            createdRelativePaths.filter { path in
                configuration.rules.contains { rule in
                    rule.scansForSensitivePatterns && rule.fix?.relativePath == path
                }
            }
        )
        return paths.sorted()
    }
}
