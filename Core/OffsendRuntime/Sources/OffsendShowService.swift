import Foundation
import WorkspacePolicyCore

/// Files of one sensitive-data type that are exposed to AI tools (not covered by
/// any effective ignore file).
public struct ShowExposedGroup: Sendable, Equatable {
    public let typeID: String
    public let typeTitle: String
    public let severity: String
    /// How to cover this data type, e.g. which ignore-file line to add.
    public let remediation: String
    public let relativePaths: [String]

    public init(typeID: String, typeTitle: String, severity: String, remediation: String, relativePaths: [String]) {
        self.typeID = typeID
        self.typeTitle = typeTitle
        self.severity = severity
        self.remediation = remediation
        self.relativePaths = relativePaths
    }
}

/// What `offsend show` found: the sensitive files that would be sent to AI tools,
/// grouped by data type.
public struct ShowReport: Sendable, Equatable {
    public let directoryPath: String
    /// Exposed sensitive files grouped by data type. Only non-empty groups are included.
    public let groups: [ShowExposedGroup]
    /// Count of unique exposed files across all groups.
    public let totalExposedCount: Int
    /// True when the workspace walk hit a file/time limit, so results may be incomplete.
    public let scanIncomplete: Bool
    public let errors: [String]

    public init(
        directoryPath: String,
        groups: [ShowExposedGroup],
        totalExposedCount: Int,
        scanIncomplete: Bool,
        errors: [String]
    ) {
        self.directoryPath = directoryPath
        self.groups = groups
        self.totalExposedCount = totalExposedCount
        self.scanIncomplete = scanIncomplete
        self.errors = errors
    }

    public var hasErrors: Bool { !errors.isEmpty }
    public var hasExposure: Bool { totalExposedCount > 0 }
}

/// Lists sensitive files that are exposed to AI tools (`.cursorignore`, `.claudeignore`, …
/// do not cover them), mirroring the macOS app's directory exposure audit. Read-only:
/// only ignore-file contents are read, never the matched files themselves.
public struct OffsendShowService: Sendable {
    private let configuration: AIWorkspacePrivacyAuditConfiguration
    private let auditor: AIWorkspacePrivacyAuditor

    public init(
        context: OffsendRuntimeContext,
        auditor: AIWorkspacePrivacyAuditor = AIWorkspacePrivacyAuditor()
    ) {
        self.init(
            configuration: OffsendConfiguration.directoryCheckConfiguration(context: context),
            auditor: auditor
        )
    }

    public init(
        configuration: AIWorkspacePrivacyAuditConfiguration,
        auditor: AIWorkspacePrivacyAuditor = AIWorkspacePrivacyAuditor()
    ) {
        self.configuration = configuration
        self.auditor = auditor
    }

    public func run(directoryURL: URL) -> ShowReport {
        let standardizedURL = directoryURL.standardizedFileURL
        let audit = auditor.audit(directoryURL: standardizedURL, configuration: configuration)

        if audit.isDirectoryUnavailable {
            return ShowReport(
                directoryPath: standardizedURL.path,
                groups: [],
                totalExposedCount: 0,
                scanIncomplete: false,
                errors: audit.errors.map(\.message)
            )
        }

        let groups = audit.sensitivePatternFindings
            .filter { !$0.exposedRelativePaths.isEmpty }
            .map { finding in
                ShowExposedGroup(
                    typeID: finding.pattern.id,
                    typeTitle: finding.pattern.title,
                    severity: finding.pattern.severity.rawValue,
                    remediation: finding.pattern.remediation,
                    relativePaths: finding.exposedRelativePaths.sorted()
                )
            }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return Self.severityRank(lhs.severity) < Self.severityRank(rhs.severity)
                }
                return lhs.typeTitle < rhs.typeTitle
            }

        return ShowReport(
            directoryPath: standardizedURL.path,
            groups: groups,
            totalExposedCount: audit.allExposedRelativePaths.count,
            scanIncomplete: !audit.exposureScanCompletion.isComplete,
            errors: audit.errors.map(\.message)
        )
    }

    /// Required exposure is the most dangerous, so it sorts first.
    private static func severityRank(_ severity: String) -> Int {
        switch severity {
        case AIWorkspacePrivacyRuleSeverity.required.rawValue: return 0
        case AIWorkspacePrivacyRuleSeverity.recommended.rawValue: return 1
        default: return 2
        }
    }
}
