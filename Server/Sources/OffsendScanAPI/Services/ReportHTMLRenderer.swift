import Foundation
import WorkspacePolicyCore

enum ReportHTMLRenderer {
    struct ReportContext: Sendable {
        let title: String
        let jobID: String
        let repoURL: String
        let generatedAt: String
        let expiresAtISO: String
        let score: String
        let scoreSummary: String
        let scanComplete: Bool
        let protectionFiles: [IgnoreFileRow]
        let contextFiles: [IgnoreFileRow]
        let patterns: [PatternRow]
        let fixes: [FixRow]
        let hasFixes: Bool
        /// JSON array of `{ path, contents }` for the files that resolve the findings,
        /// embedded verbatim so the "Fix it" modal can build platform-specific commands.
        let fixFilesJSON: String
        let errors: [String]
        var navScanActive: Bool = false
        var noindex: Bool = true

        struct IgnoreFileRow: Sendable {
            let name: String
            let toolName: String
            let severityLabel: String
            let severityClass: String
            let label: String
            let cssClass: String
        }

        struct PatternRow: Sendable {
            let id: String
            let title: String
            let severityLabel: String
            let severityClass: String
            let category: String
            let count: Int
        }

        struct FixRow: Sendable {
            let severityLabel: String
            let severityClass: String
            let title: String
            let detail: String
        }
    }

    static func render(
        templates: HTMLTemplateRenderer,
        jobID: String,
        repoURL: String,
        reportJSON: String,
        generatedAt: Date,
        reportTTL: Duration = .seconds(172_800)
    ) throws -> String {
        try templates.report(
            jobID: jobID,
            repoURL: repoURL,
            reportJSON: reportJSON,
            generatedAt: generatedAt,
            reportTTL: reportTTL
        )
    }

    static func makeContext(
        jobID: String,
        repoURL: String,
        reportJSON: String,
        generatedAt: Date,
        reportTTL: Duration = .seconds(172_800)
    ) -> ReportContext {
        let payload = decodePayload(reportJSON)
        let formatter = ISO8601DateFormatter()
        let fixes = buildFixes(from: payload)
        let (protectionFiles, contextFiles) = ignoreFileRows(from: payload)
        let score = privacyScore(from: payload)
        let expiresAt = generatedAt.addingTimeInterval(TimeInterval(reportTTL.components.seconds))

        return ReportContext(
            title: "Offsend AI Privacy Report",
            jobID: jobID,
            repoURL: repoURL,
            generatedAt: formatter.string(from: generatedAt),
            expiresAtISO: formatter.string(from: expiresAt),
            score: score.map { "\($0)/100" } ?? "?",
            scoreSummary: payload == nil ? "" : scoreSummaryText(from: fixes),
            scanComplete: payload?.scanComplete ?? false,
            protectionFiles: protectionFiles,
            contextFiles: contextFiles,
            patterns: exposedPatternRows(from: payload),
            fixes: fixes,
            hasFixes: !fixes.isEmpty,
            fixFilesJSON: fixFilesJSON(reportJSON: reportJSON),
            errors: payload?.errors ?? []
        )
    }

    /// Encodes the fix files for inline embedding in a `<script type="application/json">`
    /// tag. `</` is escaped so file contents can never prematurely close the script tag.
    private static func fixFilesJSON(reportJSON: String) -> String {
        let files = FixArchiveBuilder.fixFiles(reportJSON: reportJSON)
        guard !files.isEmpty,
              let data = try? JSONEncoder().encode(files),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json.replacingOccurrences(of: "</", with: "<\\/")
    }

    private struct Payload: Decodable {
        let scanComplete: Bool
        let ignoreFilesPresent: [String: Bool]
        let exposedPatterns: [Pattern]
        let errors: [String]

        struct Pattern: Decodable {
            let id: String
            let severity: String
            let category: String
            let count: Int
        }
    }

    private static func decodePayload(_ json: String) -> Payload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Lookup tables from the same rule/pattern definitions the scanner uses, so labels,
    /// severities, and remediation text in the report always match what was actually audited.
    private static let rulesByID: [String: AIWorkspacePrivacyRule] = Dictionary(
        uniqueKeysWithValues: AIWorkspacePrivacyRule.defaultRules.map { ($0.id, $0) }
    )

    private static let patternsByID: [String: AIWorkspaceSensitivePattern] = Dictionary(
        uniqueKeysWithValues: AIWorkspaceSensitivePattern.defaultPatterns.map { ($0.id, $0) }
    )

    private static func severity(from raw: String) -> AIWorkspacePrivacyRuleSeverity {
        AIWorkspacePrivacyRuleSeverity(rawValue: raw) ?? .informational
    }

    private static func severityRank(_ severity: AIWorkspacePrivacyRuleSeverity) -> Int {
        switch severity {
        case .required: return 0
        case .recommended: return 1
        case .informational: return 2
        }
    }

    private static func severityLabel(_ severity: AIWorkspacePrivacyRuleSeverity) -> String {
        switch severity {
        case .required: return "Required"
        case .recommended: return "Recommended"
        case .informational: return "Informational"
        }
    }

    /// Maps to the `.badge-{class}` and text-color CSS classes in site.css.
    private static func severityClass(_ severity: AIWorkspacePrivacyRuleSeverity) -> String {
        switch severity {
        case .required: return "bad"
        case .recommended: return "warn"
        case .informational: return "info"
        }
    }

    // MARK: - Score
    //
    // Real secret exposure drives the score far more than checkbox-style ignore-file
    // presence: a repo with leaked required-severity secrets should never score highly
    // just because its ignore files happen to exist. Only rules that actually gate AI
    // access (`scansForSensitivePatterns == true`) affect the score — purely
    // informational context files (AGENTS.md, CLAUDE.md, .gitignore, ...) do not.

    private static func exposurePenalty(_ severity: AIWorkspacePrivacyRuleSeverity) -> Int {
        switch severity {
        case .required: return 25
        case .recommended: return 10
        case .informational: return 4
        }
    }

    private static func missingProtectionPenalty(_ severity: AIWorkspacePrivacyRuleSeverity) -> Int {
        switch severity {
        case .required: return 15
        case .recommended: return 3
        case .informational: return 0
        }
    }

    private static func privacyScore(from payload: Payload?) -> Int? {
        guard let payload else { return nil }
        var score = 100

        for pattern in payload.exposedPatterns {
            score -= exposurePenalty(severity(from: pattern.severity))
        }

        for (ruleID, present) in payload.ignoreFilesPresent where !present {
            guard let rule = rulesByID[ruleID], rule.scansForSensitivePatterns else { continue }
            score -= missingProtectionPenalty(rule.severity)
        }

        return max(0, min(100, score))
    }

    private static func scoreSummaryText(from fixes: [ReportContext.FixRow]) -> String {
        guard !fixes.isEmpty else { return "No privacy issues found." }
        let required = fixes.filter { $0.severityLabel == severityLabel(.required) }.count
        let recommended = fixes.filter { $0.severityLabel == severityLabel(.recommended) }.count
        let informational = fixes.filter { $0.severityLabel == severityLabel(.informational) }.count

        var parts: [String] = []
        if required > 0 { parts.append("\(required) required") }
        if recommended > 0 { parts.append("\(recommended) recommended") }
        if informational > 0 { parts.append("\(informational) informational") }

        let noun = fixes.count == 1 ? "issue" : "issues"
        return "\(parts.joined(separator: ", ")) \(noun) found — see \"How to fix\" below."
    }

    // MARK: - Ignore files

    private static func ignoreFileRows(
        from payload: Payload?
    ) -> (protection: [ReportContext.IgnoreFileRow], context: [ReportContext.IgnoreFileRow]) {
        guard let payload else { return ([], []) }

        let entries = payload.ignoreFilesPresent.keys.sorted().map { key in
            (key: key, present: payload.ignoreFilesPresent[key] == true, rule: rulesByID[key])
        }

        let protection = entries
            .filter { $0.rule?.scansForSensitivePatterns == true }
            .sorted {
                let lhsRank = severityRank($0.rule?.severity ?? .informational)
                let rhsRank = severityRank($1.rule?.severity ?? .informational)
                return lhsRank != rhsRank ? lhsRank < rhsRank : $0.key < $1.key
            }
            .map { makeIgnoreFileRow(key: $0.key, present: $0.present, rule: $0.rule) }

        let context = entries
            .filter { $0.rule?.scansForSensitivePatterns != true }
            .map { makeIgnoreFileRow(key: $0.key, present: $0.present, rule: $0.rule) }

        return (protection, context)
    }

    private static func makeIgnoreFileRow(
        key: String,
        present: Bool,
        rule: AIWorkspacePrivacyRule?
    ) -> ReportContext.IgnoreFileRow {
        ReportContext.IgnoreFileRow(
            name: rule?.title ?? key,
            toolName: rule?.toolName ?? "—",
            severityLabel: severityLabel(rule?.severity ?? .informational),
            severityClass: severityClass(rule?.severity ?? .informational),
            label: present ? "yes" : "missing",
            cssClass: present ? "ok" : "bad"
        )
    }

    // MARK: - Exposed patterns

    private static func exposedPatternRows(from payload: Payload?) -> [ReportContext.PatternRow] {
        guard let payload else { return [] }
        return payload.exposedPatterns.map { pattern in
            let resolvedSeverity = severity(from: pattern.severity)
            return ReportContext.PatternRow(
                id: pattern.id,
                title: patternsByID[pattern.id]?.title ?? pattern.id,
                severityLabel: severityLabel(resolvedSeverity),
                severityClass: severityClass(resolvedSeverity),
                category: pattern.category,
                count: pattern.count
            )
        }
    }

    // MARK: - How to fix

    private static func buildFixes(from payload: Payload?) -> [ReportContext.FixRow] {
        guard let payload else { return [] }
        var fixes: [(rank: Int, row: ReportContext.FixRow)] = []

        for pattern in payload.exposedPatterns {
            let resolvedSeverity = severity(from: pattern.severity)
            let info = patternsByID[pattern.id]
            let title = info?.title ?? pattern.id
            let remediation = info?.remediation ?? "Exclude \(pattern.id) from AI tool access."
            let filesSuffix = pattern.count == 1 ? "1 file" : "\(pattern.count) files"
            fixes.append((
                rank: severityRank(resolvedSeverity),
                row: ReportContext.FixRow(
                    severityLabel: severityLabel(resolvedSeverity),
                    severityClass: severityClass(resolvedSeverity),
                    title: "\(title) exposed",
                    detail: "\(remediation) Found in \(filesSuffix)."
                )
            ))
        }

        for (ruleID, present) in payload.ignoreFilesPresent where !present {
            guard let rule = rulesByID[ruleID], rule.scansForSensitivePatterns else { continue }
            fixes.append((
                rank: severityRank(rule.severity),
                row: ReportContext.FixRow(
                    severityLabel: severityLabel(rule.severity),
                    severityClass: severityClass(rule.severity),
                    title: "Add \(rule.title) for \(rule.toolName)",
                    detail: rule.remediation
                )
            ))
        }

        return fixes
            .sorted { lhs, rhs in
                lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.row.title < rhs.row.title
            }
            .map(\.row)
    }
}
