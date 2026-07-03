import Foundation
import WorkspacePolicyCore

/// Derives ready-to-use AI ignore files from an anonymized scan report. Used by the
/// "Fix it" modal to build platform-specific copy-paste commands.
enum FixArchiveBuilder {
    /// One file the user should create to resolve findings: its repo-relative path
    /// and full ready-to-use contents.
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

    /// The files a user should create to pass the scan, or an empty array when there
    /// is nothing to fix.
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
}
