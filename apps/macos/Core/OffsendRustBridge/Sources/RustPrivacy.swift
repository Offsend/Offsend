import Foundation
import WorkspacePolicyCore

// MARK: - Codable snapshots (Rust JSON)

public struct RustAuditSnapshot: Codable, Equatable, Sendable {
    public let directory: String
    public let status: String
    public let ruleFindings: [RustRuleFindingSnapshot]
    public let sensitivePatternFindings: [RustSensitivePatternFindingSnapshot]
    public let errors: [RustErrorSnapshot]
    public let missingSensitivePatterns: [String]
    public let missingRequiredRules: [String]

    public init(
        directory: String,
        status: String,
        ruleFindings: [RustRuleFindingSnapshot],
        sensitivePatternFindings: [RustSensitivePatternFindingSnapshot],
        errors: [RustErrorSnapshot],
        missingSensitivePatterns: [String],
        missingRequiredRules: [String]
    ) {
        self.directory = directory
        self.status = status
        self.ruleFindings = ruleFindings
        self.sensitivePatternFindings = sensitivePatternFindings
        self.errors = errors
        self.missingSensitivePatterns = missingSensitivePatterns
        self.missingRequiredRules = missingRequiredRules
    }
}

public struct RustRuleFindingSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let toolName: String
    public let title: String
    public let severity: String
    public let satisfied: Bool
    public let matchedPaths: [String]
    public let exposedPaths: [String]

    public init(
        id: String,
        toolName: String,
        title: String,
        severity: String,
        satisfied: Bool,
        matchedPaths: [String],
        exposedPaths: [String]
    ) {
        self.id = id
        self.toolName = toolName
        self.title = title
        self.severity = severity
        self.satisfied = satisfied
        self.matchedPaths = matchedPaths
        self.exposedPaths = exposedPaths
    }
}

public struct RustSensitivePatternFindingSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let severity: String
    public let exposedPaths: [String]
    public let canonicalLine: String

    public init(
        id: String,
        title: String,
        severity: String,
        exposedPaths: [String],
        canonicalLine: String
    ) {
        self.id = id
        self.title = title
        self.severity = severity
        self.exposedPaths = exposedPaths
        self.canonicalLine = canonicalLine
    }
}

public struct RustErrorSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let message: String

    public init(id: String, message: String) {
        self.id = id
        self.message = message
    }
}

public struct RustFixSnapshot: Codable, Equatable, Sendable {
    public let createdRelativePaths: [String]
    public let updatedRelativePaths: [String]
    public let errors: [RustErrorSnapshot]

    public init(
        createdRelativePaths: [String],
        updatedRelativePaths: [String],
        errors: [RustErrorSnapshot]
    ) {
        self.createdRelativePaths = createdRelativePaths
        self.updatedRelativePaths = updatedRelativePaths
        self.errors = errors
    }

    public var didChangeFiles: Bool {
        !createdRelativePaths.isEmpty || !updatedRelativePaths.isEmpty
    }
}

private struct RustFixSelectionDTO: Encodable {
    let ruleIDs: [String]
    let patternIDs: [String]
}

private struct RustAuditOptionsDTO: Encodable {
    let disabledRuleIDs: [String]
    let additionalSkippedDirectoryNames: [String]
    let customIgnoreTemplate: String?
    let loadProjectConfig: Bool
}

// MARK: - Bridge

public enum RustPrivacyBridge {
    public static func audit(
        directory: URL,
        configuration: AIWorkspacePrivacyAuditConfiguration = .default
    ) throws -> RustAuditSnapshot {
        let path = directory.path
        let optionsJSON = try encodeOptions(from: configuration)
        let json = try path.withCString { cPath in
            try optionsJSON.withCString { cOptions in
                try RustFFI.call { errOut in
                    offsend_privacy_audit(cPath, cOptions, errOut)
                }
            }
        }
        return try RustFFI.decode(RustAuditSnapshot.self, from: json)
    }

    public static func fix(
        directory: URL,
        ruleIDs: Set<String>?,
        patternIDs: Set<String>?,
        configuration: AIWorkspacePrivacyAuditConfiguration = .default
    ) throws -> RustFixSnapshot {
        let path = directory.path
        let optionsJSON = try encodeOptions(from: configuration)
        let selectionJSON: String?
        if ruleIDs != nil || patternIDs != nil {
            let dto = RustFixSelectionDTO(
                ruleIDs: Array(ruleIDs ?? []).sorted(),
                patternIDs: Array(patternIDs ?? []).sorted()
            )
            selectionJSON = String(data: try JSONEncoder().encode(dto), encoding: .utf8)
        } else {
            selectionJSON = nil
        }

        let json = try path.withCString { cPath -> String in
            try optionsJSON.withCString { cOptions in
                if let selectionJSON {
                    return try selectionJSON.withCString { cSelection in
                        try RustFFI.call { errOut in
                            offsend_privacy_fix(cPath, cSelection, cOptions, errOut)
                        }
                    }
                }
                return try RustFFI.call { errOut in
                    offsend_privacy_fix(cPath, nil, cOptions, errOut)
                }
            }
        }
        return try RustFFI.decode(RustFixSnapshot.self, from: json)
    }

    /// Audit via Rust and map onto WorkspacePolicyCore models (best-effort by rule/pattern id).
    public static func auditAndMap(
        directory: URL,
        configuration: AIWorkspacePrivacyAuditConfiguration = .default
    ) throws -> AIWorkspacePrivacyAuditResult {
        let snapshot = try audit(directory: directory, configuration: configuration)
        return RustPrivacyMapper.mapAudit(snapshot, configuration: configuration)
    }

    public static func fixAndMap(
        directory: URL,
        ruleIDs: Set<String>?,
        patternIDs: Set<String>?,
        configuration: AIWorkspacePrivacyAuditConfiguration = .default
    ) throws -> AIWorkspacePrivacyFixResult {
        let snapshot = try fix(
            directory: directory,
            ruleIDs: ruleIDs,
            patternIDs: patternIDs,
            configuration: configuration
        )
        return RustPrivacyMapper.mapFix(snapshot)
    }

    private static func encodeOptions(
        from configuration: AIWorkspacePrivacyAuditConfiguration
    ) throws -> String {
        let defaultIDs = Set(AIWorkspacePrivacyRule.defaultRules.map(\.id))
        let presentIDs = Set(configuration.rules.map(\.id))
        let disabled = defaultIDs.subtracting(presentIDs)
        let customTemplate = customIgnoreTemplate(from: configuration)
        let dto = RustAuditOptionsDTO(
            disabledRuleIDs: disabled.sorted(),
            additionalSkippedDirectoryNames: configuration.additionalSkippedDirectoryNames.sorted(),
            customIgnoreTemplate: customTemplate,
            loadProjectConfig: true
        )
        let data = try JSONEncoder().encode(dto)
        guard let json = String(data: data, encoding: .utf8) else {
            throw RustFFIError.invalidUTF8
        }
        return json
    }

    /// Recover custom ignore template from resolved rule fix contents when it differs from defaults.
    private static func customIgnoreTemplate(
        from configuration: AIWorkspacePrivacyAuditConfiguration
    ) -> String? {
        let defaultsByID = Dictionary(
            uniqueKeysWithValues: AIWorkspacePrivacyRule.defaultRules.map { ($0.id, $0) }
        )
        for rule in configuration.rules {
            guard let fix = rule.fix, fix.strategy != .keepManagedContent else { continue }
            guard let defaultFix = defaultsByID[rule.id]?.fix else { continue }
            if fix.contents != defaultFix.contents {
                return fix.contents
            }
        }
        return nil
    }
}

// MARK: - Mapper (thin adapter for DirectoryCheck)

public enum RustPrivacyMapper {
    public static func mapAudit(
        _ snapshot: RustAuditSnapshot,
        configuration: AIWorkspacePrivacyAuditConfiguration
    ) -> AIWorkspacePrivacyAuditResult {
        let rulesByID = Dictionary(uniqueKeysWithValues: configuration.rules.map { ($0.id, $0) })
        let patternsByID = Dictionary(
            uniqueKeysWithValues: configuration.sensitivePatterns.map { ($0.id, $0) }
        )

        let ruleFindings: [AIWorkspacePrivacyRuleFinding] = snapshot.ruleFindings.map { finding in
            let rule = rulesByID[finding.id] ?? AIWorkspacePrivacyRule(
                id: finding.id,
                toolName: finding.toolName,
                title: finding.title,
                relativePathPatterns: [],
                severity: severity(from: finding.severity),
                scansForSensitivePatterns: false,
                remediation: ""
            )
            return AIWorkspacePrivacyRuleFinding(
                rule: rule,
                matchedRelativePaths: finding.matchedPaths,
                exposedRelativePaths: finding.exposedPaths
            )
        }

        let patternFindings: [AIWorkspaceSensitivePatternFinding] = snapshot.sensitivePatternFindings.map { finding in
            let pattern = patternsByID[finding.id] ?? AIWorkspaceSensitivePattern(
                id: finding.id,
                title: finding.title,
                acceptedPatterns: [finding.canonicalLine],
                severity: severity(from: finding.severity),
                remediation: ""
            )
            return AIWorkspaceSensitivePatternFinding(
                pattern: pattern,
                matchedIgnoreFilePaths: [],
                exposedRelativePaths: finding.exposedPaths
            )
        }

        let errors = snapshot.errors.map {
            AIWorkspacePrivacyAuditError(id: $0.id, message: $0.message)
        }

        let status = AIWorkspacePrivacyAuditStatus(rawValue: snapshot.status) ?? .fail
        let directoryURL = URL(fileURLWithPath: snapshot.directory, isDirectory: true)

        return AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: status,
            ruleFindings: ruleFindings,
            sensitivePatternFindings: patternFindings,
            errors: errors
        )
    }

    public static func mapFix(_ snapshot: RustFixSnapshot) -> AIWorkspacePrivacyFixResult {
        AIWorkspacePrivacyFixResult(
            createdRelativePaths: snapshot.createdRelativePaths,
            updatedRelativePaths: snapshot.updatedRelativePaths,
            errors: snapshot.errors.map {
                AIWorkspacePrivacyAuditError(id: $0.id, message: $0.message)
            }
        )
    }

    private static func severity(from raw: String) -> AIWorkspacePrivacyRuleSeverity {
        AIWorkspacePrivacyRuleSeverity(rawValue: raw) ?? .recommended
    }
}
