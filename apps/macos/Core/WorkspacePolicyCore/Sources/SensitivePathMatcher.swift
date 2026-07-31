import Foundation

/// Matches project relative paths against curated sensitive-pattern definitions.
public enum SensitivePathMatcher {
    public static func matchingPattern(
        relativePath: String,
        patterns: [AIWorkspaceSensitivePattern]
    ) -> AIWorkspaceSensitivePattern? {
        patterns.first { pattern in
            pattern.acceptedPatterns.contains { GlobPattern($0).matches(relativePath) }
        }
    }
}
