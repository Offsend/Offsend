import Foundation

public struct AIWorkspacePrivacyAuditConfiguration: Equatable, Sendable {
    public let rules: [AIWorkspacePrivacyRule]
    public let sensitivePatterns: [AIWorkspaceSensitivePattern]
    /// Additional directory names whose descendants are skipped during the workspace walk
    /// (merged with the auditor's built-in defaults like `.git`, `node_modules`, `.build`, `DerivedData`).
    public let additionalSkippedDirectoryNames: Set<String>
    public let exposureScanLimits: SensitivePathExposureScanLimits

    public init(
        rules: [AIWorkspacePrivacyRule],
        sensitivePatterns: [AIWorkspaceSensitivePattern] = AIWorkspaceSensitivePattern.defaultPatterns,
        additionalSkippedDirectoryNames: Set<String> = [],
        exposureScanLimits: SensitivePathExposureScanLimits = .default
    ) {
        self.rules = rules
        self.sensitivePatterns = sensitivePatterns
        self.additionalSkippedDirectoryNames = additionalSkippedDirectoryNames
        self.exposureScanLimits = exposureScanLimits
    }

    public static let `default` = AIWorkspacePrivacyAuditConfiguration(
        rules: AIWorkspacePrivacyRule.defaultRules,
        sensitivePatterns: AIWorkspaceSensitivePattern.defaultPatterns
    )
}

public enum AIWorkspacePrivacyFixScenario: Equatable, Sendable {
    /// At least one scanning ignore file already exists; show updates first, then optional missing files.
    case existingPolicyFiles
    /// No scanning ignore files yet; show only files the user can create.
    case noPolicyFiles
}

public struct AIWorkspacePrivacyRule: Equatable, Identifiable, Sendable {
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

public enum AIWorkspacePrivacyRuleSeverity: String, Equatable, Sendable {
    case required
    case recommended
    case informational
}

public struct AIWorkspaceSensitivePattern: Equatable, Identifiable, Sendable {
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
        precondition(
            !acceptedPatterns.isEmpty,
            "AIWorkspaceSensitivePattern.acceptedPatterns must not be empty (id: \(id))."
        )
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

public struct AIWorkspacePrivacyAuditResult: Equatable, Sendable {
    public let directoryURL: URL
    public let status: AIWorkspacePrivacyAuditStatus
    public let ruleFindings: [AIWorkspacePrivacyRuleFinding]
    public let sensitivePatternFindings: [AIWorkspaceSensitivePatternFinding]
    public let errors: [AIWorkspacePrivacyAuditError]
    /// Paths matching sensitive patterns from the last complete or partial exposure scan.
    public let exposureIndex: SensitivePathExposureIndex?
    public let exposureScanCompletion: SensitivePathExposureScanCompletion

    public init(
        directoryURL: URL,
        status: AIWorkspacePrivacyAuditStatus,
        ruleFindings: [AIWorkspacePrivacyRuleFinding],
        sensitivePatternFindings: [AIWorkspaceSensitivePatternFinding],
        errors: [AIWorkspacePrivacyAuditError],
        exposureIndex: SensitivePathExposureIndex? = nil,
        exposureScanCompletion: SensitivePathExposureScanCompletion = .complete
    ) {
        self.directoryURL = directoryURL
        self.status = status
        self.ruleFindings = ruleFindings
        self.sensitivePatternFindings = sensitivePatternFindings
        self.errors = errors
        self.exposureIndex = exposureIndex
        self.exposureScanCompletion = exposureScanCompletion
    }

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

    /// Union of per-tool and pattern-level exposed paths from the latest audit.
    public var allExposedRelativePaths: [String] {
        Array(
            Set(
                ruleFindings.flatMap(\.exposedRelativePaths)
                    + sensitivePatternFindings.flatMap(\.exposedRelativePaths)
            )
        ).sorted()
    }

    /// True when the audited path is missing or not a readable directory.
    public var isDirectoryUnavailable: Bool {
        errors.contains { $0.id == "directory-unavailable" }
    }
}

public enum WorkspaceDirectoryAvailability {
    public static func isReadableDirectory(at url: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return fileManager.isReadableFile(atPath: url.path)
    }
}

public enum AIWorkspacePrivacyAuditStatus: String, Equatable, Sendable {
    case pass
    case warning
    case fail
}

public struct AIWorkspacePrivacyRuleFinding: Equatable, Identifiable, Sendable {
    public var id: String { rule.id }
    public let rule: AIWorkspacePrivacyRule
    public let matchedRelativePaths: [String]
    /// Sensitive paths on disk not covered by this tool's ignore file alone.
    public let exposedRelativePaths: [String]

    public var isSatisfied: Bool {
        !matchedRelativePaths.isEmpty
    }

    public init(
        rule: AIWorkspacePrivacyRule,
        matchedRelativePaths: [String],
        exposedRelativePaths: [String] = []
    ) {
        self.rule = rule
        self.matchedRelativePaths = matchedRelativePaths
        self.exposedRelativePaths = exposedRelativePaths
    }
}

public struct AIWorkspaceSensitivePatternFinding: Equatable, Identifiable, Sendable {
    public var id: String { pattern.id }
    public let pattern: AIWorkspaceSensitivePattern
    /// Ignore files that declare coverage for this pattern type (informational).
    public let matchedIgnoreFilePaths: [String]
    /// On-disk files matching this pattern that are not covered by effective ignore rules.
    public let exposedRelativePaths: [String]

    public var isSatisfied: Bool {
        exposedRelativePaths.isEmpty
    }

    public init(
        pattern: AIWorkspaceSensitivePattern,
        matchedIgnoreFilePaths: [String],
        exposedRelativePaths: [String] = []
    ) {
        self.pattern = pattern
        self.matchedIgnoreFilePaths = matchedIgnoreFilePaths
        self.exposedRelativePaths = exposedRelativePaths
    }
}

public struct AIWorkspacePrivacyAuditError: Equatable, Identifiable, Sendable {
    public let id: String
    public let message: String

    public init(id: String, message: String) {
        self.id = id
        self.message = message
    }
}

public enum AIWorkspacePrivacyFileFixStrategy: Equatable, Sendable {
    case createIfMissing
    case mergeLines
}

public struct AIWorkspacePrivacyFileFix: Equatable, Sendable {
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

public struct AIWorkspacePrivacyFixResult: Equatable, Sendable {
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
