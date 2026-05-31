import Foundation

public struct DirectoryCheckConfigurationInput: Equatable, Sendable {
    public let workspaceAuditFull: Bool
    public let disabledRuleIDs: Set<String>
    public let extraSkippedDirectories: [String]
    public let customIgnoreTemplate: String?

    public init(
        workspaceAuditFull: Bool,
        disabledRuleIDs: Set<String>,
        extraSkippedDirectories: [String],
        customIgnoreTemplate: String?
    ) {
        self.workspaceAuditFull = workspaceAuditFull
        self.disabledRuleIDs = disabledRuleIDs
        self.extraSkippedDirectories = extraSkippedDirectories
        self.customIgnoreTemplate = customIgnoreTemplate
    }
}

public enum DirectoryCheckConfigurationResolver {
    public static func resolve(_ input: DirectoryCheckConfigurationInput) -> AIWorkspacePrivacyAuditConfiguration {
        // Detection scope is identical on every tier: Free sees the full set of AI tools
        // and sensitive patterns so it gets real value (and a clear view of what Pro fixes).
        // `workspaceAuditFull` now only gates the custom ignore template below.
        let base: AIWorkspacePrivacyAuditConfiguration = .default
        let extraSkipped = Set(
            input.extraSkippedDirectories
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let customTemplate = input.workspaceAuditFull
            ? trimmedCustomTemplate(input.customIgnoreTemplate)
            : nil

        let resolvedRules: [AIWorkspacePrivacyRule] = base.rules.compactMap { rule in
            if rule.severity != .required, input.disabledRuleIDs.contains(rule.id) {
                return nil
            }
            guard let customTemplate, let fix = rule.fix else { return rule }
            return AIWorkspacePrivacyRule(
                id: rule.id,
                toolName: rule.toolName,
                title: rule.title,
                relativePathPatterns: rule.relativePathPatterns,
                severity: rule.severity,
                scansForSensitivePatterns: rule.scansForSensitivePatterns,
                remediation: rule.remediation,
                fix: AIWorkspacePrivacyFileFix(
                    relativePath: fix.relativePath,
                    contents: customTemplate,
                    strategy: fix.strategy
                )
            )
        }

        return AIWorkspacePrivacyAuditConfiguration(
            rules: resolvedRules,
            sensitivePatterns: base.sensitivePatterns,
            additionalSkippedDirectoryNames: extraSkipped
        )
    }

    private static func trimmedCustomTemplate(_ contents: String?) -> String? {
        guard let contents else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
