import Foundation

public struct AIWorkspacePrivacyAuditConfiguration: Equatable {
    public let rules: [AIWorkspacePrivacyRule]
    public let sensitivePatterns: [AIWorkspaceSensitivePattern]

    public init(
        rules: [AIWorkspacePrivacyRule],
        sensitivePatterns: [AIWorkspaceSensitivePattern] = AIWorkspaceSensitivePattern.defaultPatterns
    ) {
        self.rules = rules
        self.sensitivePatterns = sensitivePatterns
    }

    public static let `default` = AIWorkspacePrivacyAuditConfiguration(
        rules: AIWorkspacePrivacyRule.defaultRules,
        sensitivePatterns: AIWorkspaceSensitivePattern.defaultPatterns
    )

    /// Free tier: Cursor required checks and required sensitive ignore patterns only.
    public static let freeTier = AIWorkspacePrivacyAuditConfiguration(
        rules: AIWorkspacePrivacyRule.defaultRules.filter { $0.severity == .required },
        sensitivePatterns: AIWorkspaceSensitivePattern.defaultPatterns.filter { $0.severity == .required }
    )
}

public struct AIWorkspacePrivacyRule: Equatable, Identifiable {
    public let id: String
    public let toolName: String
    public let title: String
    public let relativePathPatterns: [String]
    public let severity: AIWorkspacePrivacyRuleSeverity
    public let scansForSensitivePatterns: Bool
    public let remediation: String
    public let fix: AIWorkspacePrivacyFileFix?

    public init(
        id: String,
        toolName: String,
        title: String,
        relativePathPatterns: [String],
        severity: AIWorkspacePrivacyRuleSeverity,
        scansForSensitivePatterns: Bool,
        remediation: String,
        fix: AIWorkspacePrivacyFileFix? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.title = title
        self.relativePathPatterns = relativePathPatterns
        self.severity = severity
        self.scansForSensitivePatterns = scansForSensitivePatterns
        self.remediation = remediation
        self.fix = fix
    }
}

public enum AIWorkspacePrivacyRuleSeverity: String, Equatable {
    case required
    case recommended
    case informational
}

public struct AIWorkspaceSensitivePattern: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let acceptedPatterns: [String]
    public let severity: AIWorkspacePrivacyRuleSeverity
    public let remediation: String

    public init(
        id: String,
        title: String,
        acceptedPatterns: [String],
        severity: AIWorkspacePrivacyRuleSeverity = .recommended,
        remediation: String
    ) {
        self.id = id
        self.title = title
        self.acceptedPatterns = acceptedPatterns
        self.severity = severity
        self.remediation = remediation
    }

    /// Preferred ignore-file line when auto-fixing missing coverage.
    public var canonicalIgnoreLine: String {
        acceptedPatterns.first { pattern in
            !pattern.contains("**") && pattern.contains("*")
        }
        ?? acceptedPatterns.first { !$0.contains("**") }
        ?? acceptedPatterns[0]
    }
}

public struct AIWorkspacePrivacyAuditResult: Equatable {
    public let directoryURL: URL
    public let status: AIWorkspacePrivacyAuditStatus
    public let ruleFindings: [AIWorkspacePrivacyRuleFinding]
    public let sensitivePatternFindings: [AIWorkspaceSensitivePatternFinding]
    public let errors: [AIWorkspacePrivacyAuditError]

    public var missingRequiredRules: [AIWorkspacePrivacyRuleFinding] {
        ruleFindings.filter { !$0.isSatisfied && $0.rule.severity == .required }
    }

    public var missingRecommendedRules: [AIWorkspacePrivacyRuleFinding] {
        ruleFindings.filter { !$0.isSatisfied && $0.rule.severity == .recommended }
    }

    public var missingSensitivePatterns: [AIWorkspaceSensitivePatternFinding] {
        sensitivePatternFindings.filter { !$0.isSatisfied }
    }

    public var foundRelativePaths: [String] {
        ruleFindings.flatMap(\.matchedRelativePaths).sorted()
    }
}

public enum AIWorkspacePrivacyAuditStatus: String, Equatable {
    case pass
    case warning
    case fail
}

public struct AIWorkspacePrivacyRuleFinding: Equatable, Identifiable {
    public var id: String { rule.id }
    public let rule: AIWorkspacePrivacyRule
    public let matchedRelativePaths: [String]

    public var isSatisfied: Bool {
        !matchedRelativePaths.isEmpty
    }
}

public struct AIWorkspaceSensitivePatternFinding: Equatable, Identifiable {
    public var id: String { pattern.id }
    public let pattern: AIWorkspaceSensitivePattern
    public let matchedIgnoreFilePaths: [String]

    public var isSatisfied: Bool {
        !matchedIgnoreFilePaths.isEmpty
    }
}

public struct AIWorkspacePrivacyAuditError: Equatable, Identifiable {
    public let id: String
    public let message: String

    public init(id: String, message: String) {
        self.id = id
        self.message = message
    }
}

public enum AIWorkspacePrivacyFileFixStrategy: Equatable {
    case createIfMissing
    case mergeLines
}

public struct AIWorkspacePrivacyFileFix: Equatable {
    public let relativePath: String
    public let contents: String
    public let strategy: AIWorkspacePrivacyFileFixStrategy

    public init(
        relativePath: String,
        contents: String,
        strategy: AIWorkspacePrivacyFileFixStrategy = .mergeLines
    ) {
        self.relativePath = relativePath
        self.contents = contents
        self.strategy = strategy
    }
}

public struct AIWorkspacePrivacyFixResult: Equatable {
    public let createdRelativePaths: [String]
    public let updatedRelativePaths: [String]
    public let errors: [AIWorkspacePrivacyAuditError]

    public init(
        createdRelativePaths: [String],
        updatedRelativePaths: [String],
        errors: [AIWorkspacePrivacyAuditError]
    ) {
        self.createdRelativePaths = createdRelativePaths
        self.updatedRelativePaths = updatedRelativePaths
        self.errors = errors
    }

    public var didChangeFiles: Bool {
        !createdRelativePaths.isEmpty || !updatedRelativePaths.isEmpty
    }
}
