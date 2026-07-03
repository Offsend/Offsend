import Foundation
import WorkspacePolicyCore

/// Server-local copy of `OffsendReportService` without macOS runtime dependencies.
public struct ScanReportService {
    private let configuration: AIWorkspacePrivacyAuditConfiguration
    private let auditor: AIWorkspacePrivacyAuditor

    public init(
        configuration: AIWorkspacePrivacyAuditConfiguration = .default,
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

public struct ReportIgnoreFilePresence: Sendable, Equatable {
    public let ruleID: String
    public let present: Bool
}

public struct ReportExposedPattern: Sendable, Equatable {
    public let patternID: String
    public let severity: String
    public let category: String
    public let count: Int
}

public struct PrivacyReport: Sendable, Equatable {
    public let rulesetVersion: String
    public let scanComplete: Bool
    public let ignoreFiles: [ReportIgnoreFilePresence]
    public let exposedPatterns: [ReportExposedPattern]
    public let totalExposedFiles: Int
    public let errorIDs: [String]

    public var hasErrors: Bool { !errorIDs.isEmpty }
}
