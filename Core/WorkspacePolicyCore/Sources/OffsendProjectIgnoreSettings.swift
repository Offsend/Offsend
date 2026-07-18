import Foundation

/// Minimal reader for the `ignore:` section of `.offsend.yml`.
///
/// WorkspacePolicyCore has no YAML dependency (it is vendored into the scan
/// server), so this parses only the flat subset `offsend init` generates:
/// a top-level `ignore:` mapping with `commit:` and `tools:` (block or flow
/// list). Full config parsing stays in OffsendRuntime's `ProjectConfigLoader`.
public struct OffsendProjectIgnoreSettings: Equatable, Sendable {
    public static let configFilename = ".offsend.yml"

    /// `ignore.commit` — false/absent means AI ignore files are kept out of git
    /// and materialized locally by `offsend ignore --sync`.
    public let commitIgnoreFiles: Bool
    /// `ignore.tools` narrowing. `nil` means all supported tools.
    public let toolIDs: Set<AIWorkspaceToolID>?

    public init(commitIgnoreFiles: Bool = false, toolIDs: Set<AIWorkspaceToolID>? = nil) {
        self.commitIgnoreFiles = commitIgnoreFiles
        self.toolIDs = toolIDs
    }

    /// Reads `.offsend.yml` at the directory root. `nil` when the file is
    /// missing or unreadable (the workspace is not offsend-managed).
    public static func read(
        directoryURL: URL,
        fileManager: FileManager = .default
    ) -> OffsendProjectIgnoreSettings? {
        let url = directoryURL.standardizedFileURL.appendingPathComponent(configFilename)
        guard fileManager.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return parse(contents)
    }

    public static func parse(_ yaml: String) -> OffsendProjectIgnoreSettings {
        var commit = false
        var toolSlugs: [String] = []
        var inIgnoreSection = false
        var collectingTools = false

        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = strippingComment(String(rawLine))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let indent = line.prefix(while: { $0 == " " }).count
            if indent == 0 {
                inIgnoreSection = trimmed == "ignore:"
                collectingTools = false
                continue
            }
            guard inIgnoreSection else { continue }

            if trimmed.hasPrefix("-") {
                if collectingTools {
                    let item = unquote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                    if !item.isEmpty {
                        toolSlugs.append(item)
                    }
                }
                continue
            }

            collectingTools = false
            if let value = scalarValue(of: "commit", in: trimmed) {
                commit = value.lowercased() == "true"
            } else if let value = scalarValue(of: "tools", in: trimmed) {
                if value.isEmpty {
                    collectingTools = true
                } else if value.hasPrefix("[") {
                    toolSlugs = flowListItems(value)
                }
            }
        }

        let ids = Set(toolSlugs.compactMap { AIWorkspaceToolID(rawValue: $0.lowercased()) })
        return OffsendProjectIgnoreSettings(
            commitIgnoreFiles: commit,
            toolIDs: ids.isEmpty ? nil : ids
        )
    }

    private static func scalarValue(of key: String, in trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix("\(key):") else { return nil }
        return unquote(
            String(trimmedLine.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
        )
    }

    private static func flowListItems(_ value: String) -> [String] {
        var inner = value
        if inner.hasPrefix("[") { inner.removeFirst() }
        if inner.hasSuffix("]") { inner.removeLast() }
        return inner
            .split(separator: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    /// Drops `# …` comments (tool slugs and booleans never contain `#`).
    private static func strippingComment(_ line: String) -> String {
        guard let hashIndex = line.firstIndex(of: "#") else { return line }
        if hashIndex == line.startIndex {
            return ""
        }
        let before = line[line.index(before: hashIndex)]
        return before == " " || before == "\t" ? String(line[..<hashIndex]) : line
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

public extension AIWorkspacePrivacyRule {
    /// True when `offsend ignore --sync` materializes this rule's file locally
    /// (managed ignore files and `keepManagedContent` rule files). With
    /// `ignore.commit: false` these are gitignored, so their absence from a
    /// fresh clone or CI checkout is expected — not a missing protection.
    var isMaterializedByIgnoreSync: Bool {
        guard let fix else { return false }
        return scansForSensitivePatterns || fix.strategy == .keepManagedContent
    }
}
