import Foundation

public enum ProjectConfigIgnoreMutatorError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedPatternsValue(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPatternsValue(let value):
            return "Cannot merge into ignore.patterns: unsupported YAML value \"\(value)\". Use a list (block or [\"a\", \"b\"] flow style)."
        }
    }
}

/// String-level edits for the `ignore` section of `.offsend.yml`.
public enum ProjectConfigIgnoreMutator: Sendable {
    /// Merges patterns into `ignore.patterns`, creating the `ignore` section when missing.
    /// Preserves surrounding YAML when possible.
    public static func mergingPatterns(
        intoYAML yaml: String,
        patterns: [String]
    ) throws -> (yaml: String, added: [String]) {
        let normalized = OffsendManagedIgnoreBlock.normalizePatterns(patterns)
        guard !normalized.isEmpty else {
            return (yaml.hasSuffix("\n") ? yaml : yaml + "\n", [])
        }

        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let ignoreIndex = lines.firstIndex(where: { isIgnoreKey($0) }) {
            return try mergeIntoExistingIgnoreSection(
                lines: lines,
                ignoreIndex: ignoreIndex,
                patterns: normalized
            )
        }

        return appendIgnoreSection(to: lines, patterns: normalized)
    }

    private static func mergeIntoExistingIgnoreSection(
        lines: [String],
        ignoreIndex: Int,
        patterns: [String]
    ) throws -> (yaml: String, added: [String]) {
        var patternsLineIndex: Int?
        var listEnd: Int?
        var existing: [String] = []

        for j in (ignoreIndex + 1)..<lines.count {
            let raw = lines[j]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let indent = leadingSpaces(raw)
            if !trimmed.isEmpty, !trimmed.hasPrefix("#"), indent == 0 {
                break
            }
            if trimmed.hasPrefix("patterns:") {
                patternsLineIndex = j
                let inline = trimmed.dropFirst("patterns:".count).trimmingCharacters(in: .whitespaces)
                if inline == "[]" {
                    listEnd = j
                } else if inline.hasPrefix("[") {
                    // Flow-style list: keep its items so they are merged, not lost.
                    guard let items = parseFlowList(inline) else {
                        throw ProjectConfigIgnoreMutatorError.unsupportedPatternsValue(inline)
                    }
                    existing = items
                    listEnd = j
                } else if !inline.isEmpty, !inline.hasPrefix("#") {
                    throw ProjectConfigIgnoreMutatorError.unsupportedPatternsValue(inline)
                } else {
                    var end = j
                    for k in (j + 1)..<lines.count {
                        let item = lines[k].trimmingCharacters(in: .whitespaces)
                        let itemIndent = leadingSpaces(lines[k])
                        if item.hasPrefix("-") && itemIndent > 0 {
                            existing.append(parseListItem(item))
                            end = k
                        } else if item.isEmpty || item.hasPrefix("#") {
                            continue
                        } else {
                            break
                        }
                    }
                    listEnd = end
                }
                break
            }
        }

        let merge = ProjectConfigTemplates.mergeExcludeLists(existing: existing, additional: patterns)
        let patternsBlock = renderPatternsBlock(patterns: merge.merged)

        guard let patternsLineIndex, let listEnd else {
            // ignore: exists but no patterns key — insert patterns after ignore:
            var newLines = lines
            let insertion = patternsBlock.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            newLines.insert(contentsOf: insertion, at: ignoreIndex + 1)
            let result = newLines.joined(separator: "\n")
            return (result.hasSuffix("\n") ? result : result + "\n", merge.added)
        }

        var newLines = Array(lines.prefix(patternsLineIndex))
        newLines.append(contentsOf: patternsBlock.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        if listEnd + 1 < lines.count {
            newLines.append(contentsOf: lines[(listEnd + 1)...])
        }
        let result = newLines.joined(separator: "\n")
        return (result.hasSuffix("\n") ? result : result + "\n", merge.added)
    }

    private static func appendIgnoreSection(
        to lines: [String],
        patterns: [String]
    ) -> (yaml: String, added: [String]) {
        var newLines = lines
        if newLines.last == "" {
            newLines.removeLast()
        }
        // Insert before hooks: when present so ignore sits near the top.
        let blockLines = renderIgnoreSection(commit: false, patterns: patterns)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if let hooksIndex = newLines.firstIndex(where: {
            guard leadingSpaces($0) == 0 else { return false }
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t == "hooks:" || t.hasPrefix("hooks:")
        }) {
            if hooksIndex > 0, newLines[hooksIndex - 1].trimmingCharacters(in: .whitespaces).isEmpty == false {
                newLines.insert("", at: hooksIndex)
                newLines.insert(contentsOf: blockLines, at: hooksIndex)
                newLines.insert("", at: hooksIndex + blockLines.count + 1)
            } else {
                newLines.insert(contentsOf: blockLines, at: hooksIndex)
                newLines.insert("", at: hooksIndex + blockLines.count)
            }
        } else {
            newLines.append("")
            newLines.append(contentsOf: blockLines)
            newLines.append("")
        }
        return (newLines.joined(separator: "\n"), patterns)
    }

    public static func renderIgnoreSection(commit: Bool, patterns: [String]) -> String {
        var lines = [
            "ignore:",
            "  commit: \(commit ? "true" : "false")",
        ]
        lines.append(renderPatternsBlock(patterns: patterns))
        return lines.joined(separator: "\n")
    }

    private static func renderPatternsBlock(patterns: [String]) -> String {
        if patterns.isEmpty {
            return "  patterns: []"
        }
        let items = patterns.map { "    - \"\($0)\"" }.joined(separator: "\n")
        return "  patterns:\n\(items)"
    }

    /// Matches only a top-level `ignore:` key so nested keys with the same name
    /// (e.g. inside another section) are never mistaken for the ignore section.
    private static func isIgnoreKey(_ line: String) -> Bool {
        guard leadingSpaces(line) == 0 else { return false }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "ignore:" || trimmed.hasPrefix("ignore:")
    }

    /// Parses a single-line flow sequence like `["a", 'b', c]`, tolerating a
    /// trailing `# comment`. Returns nil when the value is not a complete list.
    private static func parseFlowList(_ inline: String) -> [String]? {
        guard inline.hasPrefix("["), let closing = inline.lastIndex(of: "]") else { return nil }
        let tail = inline[inline.index(after: closing)...].trimmingCharacters(in: .whitespaces)
        guard tail.isEmpty || tail.hasPrefix("#") else { return nil }
        let body = inline[inline.index(after: inline.startIndex)..<closing]
        return body
            .split(separator: ",")
            .map { item -> String in
                var value = item.trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                return value
            }
            .filter { !$0.isEmpty }
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    private static func parseListItem(_ trimmed: String) -> String {
        var value = trimmed
        if value.hasPrefix("-") {
            value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}
