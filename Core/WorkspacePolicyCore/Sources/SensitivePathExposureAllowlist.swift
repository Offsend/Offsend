import Foundation

/// Paths that match sensitive globs but are safe to exclude from exposure findings.
public enum SensitivePathExposureAllowlist {
    public static let defaultPatterns: [String] = [
        ".env.example",
        "**/.env.example",
        // Common non-secret `*.key` names (still match key-files glob).
        "public.key",
        "**/public.key",
        "license.key",
        "**/license.key",
        "licence.key",
        "**/licence.key",
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
