import Foundation
import WorkspacePolicyCore

/// Turns an anonymized scan report into a downloadable "fix pack": ready-to-use
/// AI ignore files with full coverage of the sensitive patterns, so dropping the
/// archive into a repository root makes it pass the scan. Ships the files a repo
/// is missing, and — when sensitive files are still exposed — refreshes the
/// existing gating ignore files too (they are present but incomplete).
enum FixArchiveBuilder {
    static let fileName = "offsend-fix.zip"

    /// One file the user should create to resolve findings: its repo-relative path
    /// and full ready-to-use contents. Used to build both the zip and the copy-paste
    /// "Fix it" commands shown on the report page.
    struct FixFile: Sendable, Equatable, Encodable {
        let path: String
        let contents: String
    }

    private struct Payload: Decodable {
        let ignoreFilesPresent: [String: Bool]
        let exposedPatterns: [ExposedPattern]

        struct ExposedPattern: Decodable {
            let id: String
        }
    }

    private static let rulesByID: [String: AIWorkspacePrivacyRule] = Dictionary(
        uniqueKeysWithValues: AIWorkspacePrivacyRule.defaultRules.map { ($0.id, $0) }
    )

    private static let patternsByID: [String: AIWorkspaceSensitivePattern] = Dictionary(
        uniqueKeysWithValues: AIWorkspaceSensitivePattern.defaultPatterns.map { ($0.id, $0) }
    )

    /// Whether the report has any fixable finding worth generating an archive for.
    static func hasFixes(reportJSON: String) -> Bool {
        guard let payload = decode(reportJSON) else { return false }
        return !missingIgnoreRules(from: payload).isEmpty || !exposedPatterns(from: payload).isEmpty
    }

    /// The zip bytes, or `nil` when there is nothing to fix.
    static func makeArchive(reportJSON: String, repoURL: String) -> Data? {
        guard let payload = decode(reportJSON) else { return nil }
        let missing = missingIgnoreRules(from: payload)
        let patterns = exposedPatterns(from: payload)
        guard !missing.isEmpty || !patterns.isEmpty else { return nil }

        // Exposed patterns mean at least one existing gating ignore file is
        // incomplete, so refresh present files with full-coverage content too.
        let refreshed = patterns.isEmpty ? [] : presentIgnoreRules(from: payload)

        var entries = fixFiles(missing: missing, refreshed: refreshed).map {
            ZIPArchive.Entry(path: $0.path, contents: $0.contents)
        }
        entries.append(
            ZIPArchive.Entry(
                path: "README.md",
                contents: readme(repoURL: repoURL, missing: missing, refreshed: refreshed, patterns: patterns)
            )
        )
        return ZIPArchive.archive(entries: entries)
    }

    /// The files a user should create to pass the scan, or an empty array when there
    /// is nothing to fix. Same content as the zip, minus the README.
    static func fixFiles(reportJSON: String) -> [FixFile] {
        guard let payload = decode(reportJSON) else { return [] }
        let missing = missingIgnoreRules(from: payload)
        let patterns = exposedPatterns(from: payload)
        guard !missing.isEmpty || !patterns.isEmpty else { return [] }
        let refreshed = patterns.isEmpty ? [] : presentIgnoreRules(from: payload)
        return fixFiles(missing: missing, refreshed: refreshed)
    }

    private static func fixFiles(
        missing: [AIWorkspacePrivacyRule],
        refreshed: [AIWorkspacePrivacyRule]
    ) -> [FixFile] {
        var files: [FixFile] = []
        var writtenPaths = Set<String>()
        for rule in missing + refreshed {
            guard let fix = rule.fix, writtenPaths.insert(fix.relativePath).inserted else { continue }
            files.append(FixFile(path: fix.relativePath, contents: fix.contents))
        }
        return files
    }

    private static func decode(_ json: String) -> Payload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Missing ignore files that actually gate AI access (skip informational/context files).
    private static func missingIgnoreRules(from payload: Payload) -> [AIWorkspacePrivacyRule] {
        gatingRules(from: payload, present: false)
    }

    /// Present gating ignore files, refreshed when their coverage has a gap.
    private static func presentIgnoreRules(from payload: Payload) -> [AIWorkspacePrivacyRule] {
        gatingRules(from: payload, present: true)
    }

    private static func gatingRules(from payload: Payload, present: Bool) -> [AIWorkspacePrivacyRule] {
        payload.ignoreFilesPresent
            .filter { $0.value == present }
            .compactMap { rulesByID[$0.key] }
            .filter { $0.scansForSensitivePatterns && $0.severity != .informational && $0.fix != nil }
            .sorted { ($0.fix?.relativePath ?? "") < ($1.fix?.relativePath ?? "") }
    }

    private static func exposedPatterns(from payload: Payload) -> [AIWorkspaceSensitivePattern] {
        var seen = Set<String>()
        return payload.exposedPatterns.compactMap { exposed in
            guard seen.insert(exposed.id).inserted else { return nil }
            return patternsByID[exposed.id]
        }
    }

    private static func readme(
        repoURL: String,
        missing: [AIWorkspacePrivacyRule],
        refreshed: [AIWorkspacePrivacyRule],
        patterns: [AIWorkspaceSensitivePattern]
    ) -> String {
        var lines: [String] = [
            "# Offsend fix pack",
            "",
            "Repository: \(repoURL)",
            "",
            "This archive contains ready-to-use AI ignore files with full coverage of the",
            "sensitive patterns found in your scan. They stop AI tools and agents from reading",
            "secrets, credentials, and other sensitive files.",
            "",
            "## How to apply",
            "",
            "1. Unzip this archive into the root of your repository.",
            "2. Commit the files.",
        ]

        if !refreshed.isEmpty {
            lines.append(
                "3. These files replace existing ignore files with a complete Offsend-recommended"
            )
            lines.append(
                "   version. If you had custom rules, merge them back in after unzipping."
            )
        }

        if !missing.isEmpty {
            lines.append("")
            lines.append("## New ignore files")
            lines.append("")
            for rule in missing {
                guard let path = rule.fix?.relativePath else { continue }
                lines.append("- `\(path)` — \(rule.toolName)")
            }
        }

        if !refreshed.isEmpty {
            lines.append("")
            lines.append("## Updated ignore files (existing but incomplete)")
            lines.append("")
            for rule in refreshed {
                guard let path = rule.fix?.relativePath else { continue }
                lines.append("- `\(path)` — \(rule.toolName)")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }
}
