import Foundation

/// Paths that match sensitive globs but are safe to exclude from exposure findings.
public enum SensitivePathExposureAllowlist {
    public static let defaultPatterns: [String] = [
        ".env.example",
        "**/.env.example",
        "Tests/**",
        "**/Tests/**",
        "test/**",
        "**/test/**",
        "**/*Tests/**",
        "**/*tests/**"
    ]

    public static func isAllowlisted(relativePath: String, patterns: [String] = defaultPatterns) -> Bool {
        patterns.contains { GlobPattern($0).matches(relativePath) }
    }
}
