import Foundation

/// Upserts a managed pattern section in gitignore-style files without touching
/// user-authored lines outside the markers.
///
/// Blocks can be namespaced with a `section` label so independent writers
/// (ignore-file sync vs hook install) never clobber each other:
///
/// ```text
/// # >>> offsend managed: ignore-files
/// .cursorignore
/// # <<< offsend managed: ignore-files
/// ```
public enum OffsendManagedIgnoreBlock: Sendable {
    public static let startMarker = "# >>> offsend managed"
    public static let endMarker = "# <<< offsend managed"

    public static func startMarker(section: String?) -> String {
        section.map { "\(startMarker): \($0)" } ?? startMarker
    }

    public static func endMarker(section: String?) -> String {
        section.map { "\(endMarker): \($0)" } ?? endMarker
    }

    public enum UpsertResult: Equatable, Sendable {
        case created
        case updated
        case unchanged
        case malformed(String)
    }

    /// Returns updated file contents and whether they changed. When multiple
    /// blocks of the same section exist (e.g. after a merge conflict), the first
    /// is replaced and the duplicates are removed.
    public static func upsert(
        patterns: [String],
        into contents: String?,
        section: String? = nil
    ) -> (contents: String, result: UpsertResult) {
        let normalized = normalizePatterns(patterns)
        let blockLines = renderBlockLines(patterns: normalized, section: section)

        guard let existing = contents else {
            return (blockLines.joined(separator: "\n") + "\n", .created)
        }

        var lines = splitLines(existing)

        let ranges: [ClosedRange<Int>]
        switch blockRanges(in: lines, section: section) {
        case .failure(let message):
            return (ensureTrailingNewline(existing), .malformed(message))
        case .success(let found):
            ranges = found
        }

        var newLines: [String] = []
        if ranges.isEmpty {
            newLines = lines
            if let last = newLines.last, !last.isEmpty {
                newLines.append("")
            }
            newLines.append(contentsOf: blockLines)
        } else {
            var index = 0
            var replaced = false
            while index < lines.count {
                if let range = ranges.first(where: { $0.lowerBound == index }) {
                    if !replaced {
                        newLines.append(contentsOf: blockLines)
                        replaced = true
                    }
                    index = range.upperBound + 1
                    continue
                }
                newLines.append(lines[index])
                index += 1
            }
        }

        let updated = newLines.isEmpty
            ? blockLines.joined(separator: "\n") + "\n"
            : newLines.joined(separator: "\n") + "\n"
        if updated == ensureTrailingNewline(existing) {
            return (updated, .unchanged)
        }
        return (updated, .updated)
    }

    /// Removes every managed block for `section`. Returns nil when no block exists
    /// (including when the block is malformed).
    public static func removing(section: String?, from contents: String) -> String? {
        let lines = splitLines(contents)
        guard case .success(let ranges) = blockRanges(in: lines, section: section),
              !ranges.isEmpty else {
            return nil
        }
        var newLines: [String] = []
        var index = 0
        while index < lines.count {
            if let range = ranges.first(where: { $0.lowerBound == index }) {
                index = range.upperBound + 1
                continue
            }
            newLines.append(lines[index])
            index += 1
        }
        while newLines.last == "" {
            newLines.removeLast()
        }
        guard !newLines.isEmpty else { return "" }
        return newLines.joined(separator: "\n") + "\n"
    }

    /// Patterns currently listed inside the managed block (nil if absent/malformed).
    public static func patterns(in contents: String, section: String? = nil) -> [String]? {
        let lines = splitLines(contents)
        guard case .success(let ranges) = blockRanges(in: lines, section: section),
              let range = ranges.first else {
            return nil
        }
        guard range.upperBound - range.lowerBound >= 2 else { return [] }
        return normalizePatterns(Array(lines[(range.lowerBound + 1)...(range.upperBound - 1)]))
    }

    public static func normalizePatterns(_ patterns: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in patterns {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    public static func renderBlock(patterns: [String], section: String? = nil) -> String {
        renderBlockLines(patterns: patterns, section: section).joined(separator: "\n")
    }

    private static func renderBlockLines(patterns: [String], section: String?) -> [String] {
        [startMarker(section: section)] + patterns + [endMarker(section: section)]
    }

    private enum BlockScan {
        case success([ClosedRange<Int>])
        case failure(String)
    }

    /// Whole-line block boundaries. Markers must match a full trimmed line, so
    /// sectioned and unsectioned blocks never shadow each other.
    private static func blockRanges(
        in lines: [String],
        section: String?
    ) -> BlockScan {
        let start = startMarker(section: section)
        let end = endMarker(section: section)
        var ranges: [ClosedRange<Int>] = []
        var openIndex: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == start {
                guard openIndex == nil else {
                    return .failure("Ignore file has a broken offsend managed block (nested start marker).")
                }
                openIndex = index
            } else if trimmed == end {
                guard let open = openIndex else {
                    return .failure("Ignore file has a broken offsend managed block (end marker without start).")
                }
                ranges.append(open...index)
                openIndex = nil
            }
        }
        if openIndex != nil {
            return .failure("Ignore file has a broken offsend managed block (missing end marker).")
        }
        return .success(ranges)
    }

    /// Splits into whole lines, dropping the artificial empty element a trailing
    /// newline produces so callers can reason line-by-line.
    private static func splitLines(_ contents: String) -> [String] {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    private static func ensureTrailingNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? text : text + "\n"
    }
}
