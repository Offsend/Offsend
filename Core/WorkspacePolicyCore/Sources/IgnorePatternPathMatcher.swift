import Foundation

/// Matches project relative paths against lines extracted from AI ignore files.
///
/// Glob lines (`*`, `?`, `**`) use `GlobPattern`. Literal lines match the exact path
/// or any descendant when the line names a directory (with or without a trailing `/`).
public enum IgnorePatternPathMatcher {
    public static func matches(relativePath: String, ignoreLine: String) -> Bool {
        let trimmed = ignoreLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.contains("*") || trimmed.contains("?") {
            return GlobPattern(trimmed).matches(relativePath)
        }

        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard !normalized.isEmpty else { return false }

        if relativePath == normalized {
            return true
        }

        return relativePath.hasPrefix(normalized + "/")
    }

    public static func isIgnored(relativePath: String, ignoreLines: some Sequence<String>) -> Bool {
        ignoreLines.contains { matches(relativePath: relativePath, ignoreLine: $0) }
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
