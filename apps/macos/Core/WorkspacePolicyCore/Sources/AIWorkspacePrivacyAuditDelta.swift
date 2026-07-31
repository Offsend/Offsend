import Foundation

public struct AIWorkspacePrivacyAuditDelta: Equatable {
    public let previousStatus: AIWorkspacePrivacyAuditStatus
    public let currentStatus: AIWorkspacePrivacyAuditStatus
    public let newlyMissingRules: [AIWorkspacePrivacyRuleFinding]
    public let newlySatisfiedRules: [AIWorkspacePrivacyRuleFinding]
    public let newlyMissingPatterns: [AIWorkspaceSensitivePatternFinding]
    public let newlySatisfiedPatterns: [AIWorkspaceSensitivePatternFinding]
    public let addedMatchedPaths: [String]
    public let removedMatchedPaths: [String]
    public let addedExposedRelativePaths: [String]
    public let removedExposedRelativePaths: [String]

    public init(
        previousStatus: AIWorkspacePrivacyAuditStatus,
        currentStatus: AIWorkspacePrivacyAuditStatus,
        newlyMissingRules: [AIWorkspacePrivacyRuleFinding],
        newlySatisfiedRules: [AIWorkspacePrivacyRuleFinding],
        newlyMissingPatterns: [AIWorkspaceSensitivePatternFinding],
        newlySatisfiedPatterns: [AIWorkspaceSensitivePatternFinding],
        addedMatchedPaths: [String],
        removedMatchedPaths: [String],
        addedExposedRelativePaths: [String] = [],
        removedExposedRelativePaths: [String] = []
    ) {
        self.previousStatus = previousStatus
        self.currentStatus = currentStatus
        self.newlyMissingRules = newlyMissingRules
        self.newlySatisfiedRules = newlySatisfiedRules
        self.newlyMissingPatterns = newlyMissingPatterns
        self.newlySatisfiedPatterns = newlySatisfiedPatterns
        self.addedMatchedPaths = addedMatchedPaths
        self.removedMatchedPaths = removedMatchedPaths
        self.addedExposedRelativePaths = addedExposedRelativePaths
        self.removedExposedRelativePaths = removedExposedRelativePaths
    }

    public var hasChanges: Bool {
        previousStatus != currentStatus
            || !newlyMissingRules.isEmpty
            || !newlySatisfiedRules.isEmpty
            || !newlyMissingPatterns.isEmpty
            || !newlySatisfiedPatterns.isEmpty
            || !addedMatchedPaths.isEmpty
            || !removedMatchedPaths.isEmpty
            || !addedExposedRelativePaths.isEmpty
            || !removedExposedRelativePaths.isEmpty
    }

    public static func compute(
        from previous: AIWorkspacePrivacyAuditResult,
        to current: AIWorkspacePrivacyAuditResult
    ) -> AIWorkspacePrivacyAuditDelta {
        let previousRules = Dictionary(uniqueKeysWithValues: previous.ruleFindings.map { ($0.rule.id, $0) })
        let currentRules = Dictionary(uniqueKeysWithValues: current.ruleFindings.map { ($0.rule.id, $0) })

        var newlyMissingRules: [AIWorkspacePrivacyRuleFinding] = []
        var newlySatisfiedRules: [AIWorkspacePrivacyRuleFinding] = []

        for (id, currentFinding) in currentRules {
            let previousFinding = previousRules[id]
            let wasSatisfied = previousFinding?.isSatisfied ?? false
            let isSatisfied = currentFinding.isSatisfied
            if wasSatisfied && !isSatisfied {
                newlyMissingRules.append(currentFinding)
            } else if !wasSatisfied && isSatisfied {
                newlySatisfiedRules.append(currentFinding)
            }
        }

        let previousPatterns = Dictionary(uniqueKeysWithValues: previous.sensitivePatternFindings.map { ($0.pattern.id, $0) })
        let currentPatterns = Dictionary(uniqueKeysWithValues: current.sensitivePatternFindings.map { ($0.pattern.id, $0) })

        var newlyMissingPatterns: [AIWorkspaceSensitivePatternFinding] = []
        var newlySatisfiedPatterns: [AIWorkspaceSensitivePatternFinding] = []

        for (id, currentFinding) in currentPatterns {
            let previousFinding = previousPatterns[id]
            let wasSatisfied = previousFinding?.isSatisfied ?? false
            let isSatisfied = currentFinding.isSatisfied
            if wasSatisfied && !isSatisfied {
                newlyMissingPatterns.append(currentFinding)
            } else if !wasSatisfied && isSatisfied {
                newlySatisfiedPatterns.append(currentFinding)
            }
        }

        let previousPaths = Set(previous.foundRelativePaths)
        let currentPaths = Set(current.foundRelativePaths)
        let previousExposed = Set(previous.allExposedRelativePaths)
        let currentExposed = Set(current.allExposedRelativePaths)

        return AIWorkspacePrivacyAuditDelta(
            previousStatus: previous.status,
            currentStatus: current.status,
            newlyMissingRules: newlyMissingRules.sorted { $0.rule.id < $1.rule.id },
            newlySatisfiedRules: newlySatisfiedRules.sorted { $0.rule.id < $1.rule.id },
            newlyMissingPatterns: newlyMissingPatterns.sorted { $0.pattern.id < $1.pattern.id },
            newlySatisfiedPatterns: newlySatisfiedPatterns.sorted { $0.pattern.id < $1.pattern.id },
            addedMatchedPaths: currentPaths.subtracting(previousPaths).sorted(),
            removedMatchedPaths: previousPaths.subtracting(currentPaths).sorted(),
            addedExposedRelativePaths: currentExposed.subtracting(previousExposed).sorted(),
            removedExposedRelativePaths: previousExposed.subtracting(currentExposed).sorted()
        )
    }
}
