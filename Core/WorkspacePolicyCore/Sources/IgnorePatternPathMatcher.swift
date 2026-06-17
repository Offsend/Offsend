import Foundation

/// Matches project relative paths against lines extracted from AI ignore files,
/// following gitignore semantics (as used by `.cursorignore`, `.claudeignore`, …).
///
/// A pattern with a `/` anywhere but the end — or anchored by a leading `/` — is
/// matched relative to the workspace root. A pattern with no `/` matches a file or
/// directory name at any depth (so `*.pem` also covers `certs/server.pem`). A trailing
/// `/` marks a directory; its descendants are matched as well. Glob tokens (`*`, `?`,
/// `**`) are handled by `GlobPattern`.
public enum IgnorePatternPathMatcher {
    public static func matches(relativePath: String, ignoreLine: String) -> Bool {
        var pattern = ignoreLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return false }

        // A leading "/" anchors the pattern to the workspace root.
        let leadingSlash = pattern.hasPrefix("/")
        if leadingSlash {
            pattern.removeFirst()
        }
        // A trailing "/" marks a directory; descendants are still matched below.
        if pattern.hasSuffix("/") {
            pattern.removeLast()
        }
        guard !pattern.isEmpty else { return false }

        if leadingSlash || pattern.contains("/") {
            return matchesAnchored(relativePath: relativePath, pattern: pattern)
        }
        return matchesAtAnyDepth(relativePath: relativePath, pattern: pattern)
    }

    /// Matches `pattern` against the full path from the workspace root.
    private static func matchesAnchored(relativePath: String, pattern: String) -> Bool {
        if pattern.contains("*") || pattern.contains("?") {
            return GlobPattern(pattern).matches(relativePath)
        }
        return relativePath == pattern || relativePath.hasPrefix(pattern + "/")
    }

    /// Matches a slash-less `pattern` against any single path segment, so that a name
    /// matches at any depth and a matched directory segment covers its descendants.
    private static func matchesAtAnyDepth(relativePath: String, pattern: String) -> Bool {
        let segments = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if pattern.contains("*") || pattern.contains("?") {
            let glob = GlobPattern(pattern)
            return segments.contains { glob.matches($0) }
        }
        return segments.contains(pattern)
    }

    /// Lines beginning with `!` re-include a path an earlier pattern excluded
    /// (gitignore semantics). Pattern order is not preserved here (lines come from a
    /// `Set`), so a path is treated as ignored when at least one positive pattern
    /// matches and no negation pattern re-includes it within the same file.
    public static func isIgnored(relativePath: String, ignoreLines: some Sequence<String>) -> Bool {
        var hasPositiveMatch = false
        var isReincluded = false
        for line in ignoreLines {
            if let negated = negationBody(of: line) {
                if matches(relativePath: relativePath, ignoreLine: negated) {
                    isReincluded = true
                }
            } else if matches(relativePath: relativePath, ignoreLine: line) {
                hasPositiveMatch = true
            }
        }
        return hasPositiveMatch && !isReincluded
    }

    /// Returns the pattern body when `line` negates (`!foo`), or `nil` otherwise.
    private static func negationBody(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("!"), trimmed.count > 1 else { return nil }
        return String(trimmed.dropFirst())
    }

    public static func isIgnored(
        relativePath: String,
        ignorePatternsByFile: [String: Set<String>]
    ) -> Bool {
        ignorePatternsByFile.values.contains { patterns in
            isIgnored(relativePath: relativePath, ignoreLines: patterns)
        }
    }
}
