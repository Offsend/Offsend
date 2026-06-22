import Foundation
import WorkspacePolicyCore

/// Whether one AI ignore-file rule is present in the audited directory.
public struct ReportIgnoreFilePresence: Sendable, Equatable {
    public let ruleID: String
    public let present: Bool

    public init(ruleID: String, present: Bool) {
        self.ruleID = ruleID
        self.present = present
    }
}

/// One sensitive-data type that is exposed to AI tools, reduced to a count.
/// Carries no file names or paths so it is safe to publish in aggregate.
public struct ReportExposedPattern: Sendable, Equatable {
    public let patternID: String
    public let severity: String
    /// Coarse class (secret, cloud, signing, pii, history) for report roll-ups.
    public let category: String
    public let count: Int

    public init(patternID: String, severity: String, category: String, count: Int) {
        self.patternID = patternID
        self.severity = severity
        self.category = category
        self.count = count
    }
}

/// Anonymized, aggregated view of `offsend show`: which AI ignore files exist and
/// how many sensitive files are exposed per type — with no public paths or file
/// names, so a fleet of these reports can be aggregated into weekly statistics.
public struct PrivacyReport: Sendable, Equatable {
    /// Stable fingerprint of the rule + pattern set, so weekly slices stay comparable.
    public let rulesetVersion: String
    /// False when the directory was unavailable or the exposure walk hit a limit;
    /// such reports should be excluded from statistics.
    public let scanComplete: Bool
    public let ignoreFiles: [ReportIgnoreFilePresence]
    public let exposedPatterns: [ReportExposedPattern]
    public let totalExposedFiles: Int
    /// Error identifiers only (never messages, which can contain paths).
    public let errorIDs: [String]

    public init(
        rulesetVersion: String,
        scanComplete: Bool,
        ignoreFiles: [ReportIgnoreFilePresence],
        exposedPatterns: [ReportExposedPattern],
        totalExposedFiles: Int,
        errorIDs: [String]
    ) {
        self.rulesetVersion = rulesetVersion
        self.scanComplete = scanComplete
        self.ignoreFiles = ignoreFiles
        self.exposedPatterns = exposedPatterns
        self.totalExposedFiles = totalExposedFiles
        self.errorIDs = errorIDs
    }

    public var hasErrors: Bool { !errorIDs.isEmpty }
}

/// Produces an anonymized aggregate from the workspace privacy audit. Read-only:
/// like `offsend show`, only ignore-file contents are read, never the matched files.
public struct OffsendReportService: Sendable {
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

    public func run(directoryURL: URL) -> PrivacyReport {
        let standardizedURL = directoryURL.standardizedFileURL
        let audit = auditor.audit(directoryURL: standardizedURL, configuration: configuration)
        let rulesetVersion = Self.rulesetVersion(for: configuration)

        let findingByRuleID = Dictionary(
            audit.ruleFindings.map { ($0.rule.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let ignoreFiles = configuration.rules
            .sorted { $0.id < $1.id }
            .map { rule in
                ReportIgnoreFilePresence(
                    ruleID: rule.id,
                    present: findingByRuleID[rule.id]?.isSatisfied ?? false
                )
            }

        if audit.isDirectoryUnavailable {
            return PrivacyReport(
                rulesetVersion: rulesetVersion,
                scanComplete: false,
                ignoreFiles: ignoreFiles,
                exposedPatterns: [],
                totalExposedFiles: 0,
                errorIDs: audit.errors.map(\.id)
            )
        }

        let exposedPatterns = audit.sensitivePatternFindings
            .filter { !$0.exposedRelativePaths.isEmpty }
            .map { finding in
                ReportExposedPattern(
                    patternID: finding.pattern.id,
                    severity: finding.pattern.severity.rawValue,
                    category: finding.pattern.category.rawValue,
                    count: finding.exposedRelativePaths.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return Self.severityRank(lhs.severity) < Self.severityRank(rhs.severity)
                }
                return lhs.patternID < rhs.patternID
            }

        return PrivacyReport(
            rulesetVersion: rulesetVersion,
            scanComplete: audit.exposureScanCompletion.isComplete,
            ignoreFiles: ignoreFiles,
            exposedPatterns: exposedPatterns,
            totalExposedFiles: audit.allExposedRelativePaths.count,
            errorIDs: audit.errors.map(\.id)
        )
    }

    private static func severityRank(_ severity: String) -> Int {
        switch severity {
        case AIWorkspacePrivacyRuleSeverity.required.rawValue: return 0
        case AIWorkspacePrivacyRuleSeverity.recommended.rawValue: return 1
        default: return 2
        }
    }

    /// Deterministic fingerprint (stable across processes, unlike `Hasher`) over rule
    /// and pattern identities + severities, so a ruleset change is detectable in stats.
    private static func rulesetVersion(for configuration: AIWorkspacePrivacyAuditConfiguration) -> String {
        var components: [String] = []
        for rule in configuration.rules.sorted(by: { $0.id < $1.id }) {
            components.append("r:\(rule.id):\(rule.severity.rawValue)")
        }
        for pattern in configuration.sensitivePatterns.sorted(by: { $0.id < $1.id }) {
            let accepted = pattern.acceptedPatterns.joined(separator: ",")
            components.append("p:\(pattern.id):\(pattern.severity.rawValue):\(accepted)")
        }
        return djb2Hex(components.joined(separator: "|"))
    }

    private static func djb2Hex(_ string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
