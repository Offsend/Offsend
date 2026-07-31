import Foundation

public enum WorkspaceWatchRelevantPathFilter {
    public static func relevantChangedPaths(
        absolutePaths: [String],
        rootURL: URL,
        configuration: AIWorkspacePrivacyAuditConfiguration
    ) -> Set<String> {
        let rootPath = rootURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        var relativePaths = Set<String>()
        for absolutePath in absolutePaths {
            let standardized = URL(fileURLWithPath: absolutePath).standardizedFileURL.path
            if standardized == rootPath {
                relativePaths.insert("")
                continue
            }
            guard standardized.hasPrefix(prefix) else { continue }
            let relative = String(standardized.dropFirst(prefix.count))
            guard !relative.isEmpty else { continue }
            relativePaths.insert(relative)
        }

        return Set(relativePaths.filter { isPotentiallyRelevant(relativePath: $0, configuration: configuration) })
    }

    public static func isPotentiallyRelevant(
        relativePath: String,
        configuration: AIWorkspacePrivacyAuditConfiguration
    ) -> Bool {
        if relativePath.isEmpty {
            return true
        }

        let skippedDirectoryNames = SensitivePathExposureChecker.builtInSkippedDirectoryNames
            .union(configuration.additionalSkippedDirectoryNames)
        if WorkspaceWatchPathMatching.isUnderSkippedDirectory(
            relativePath,
            skippedDirectoryNames: skippedDirectoryNames
        ) {
            return false
        }

        for rule in configuration.rules {
            if WorkspaceWatchPathMatching.ruleAffects(relativePath: relativePath, rule: rule) {
                return true
            }
        }

        if SensitivePathMatcher.matchingPattern(
            relativePath: relativePath,
            patterns: configuration.sensitivePatterns
        ) != nil {
            return true
        }

        return false
    }
}

enum WorkspaceWatchPathMatching {
    static func staticDirectoryPrefix(for pattern: String) -> String {
        guard let wildcardIndex = pattern.firstIndex(where: { $0 == "*" || $0 == "?" }) else {
            return pattern
        }
        let prefix = pattern[..<wildcardIndex]
        guard let slashIndex = prefix.lastIndex(of: "/") else { return "" }
        return String(prefix[..<slashIndex])
    }

    static func path(_ lhs: String, isParentOrAncestorOf rhs: String) -> Bool {
        guard !lhs.isEmpty else { return true }
        if rhs == lhs { return true }
        return rhs.hasPrefix(lhs + "/")
    }

    static func isUnderSkippedDirectory(_ relativePath: String, skippedDirectoryNames: Set<String>) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        return components.contains(where: skippedDirectoryNames.contains)
    }

    static func pathMatchesRule(
        _ relativePath: String,
        rule: AIWorkspacePrivacyRule,
        skippedDirectoryNames: Set<String>
    ) -> Bool {
        guard !isUnderSkippedDirectory(relativePath, skippedDirectoryNames: skippedDirectoryNames) else {
            return false
        }

        for pattern in rule.relativePathPatterns {
            if pattern.contains("*") || pattern.contains("?") {
                if GlobPattern(pattern).matches(relativePath) {
                    return true
                }
            } else if relativePath == pattern {
                return true
            }
        }
        return false
    }

    static func ruleIsAffected(
        rule: AIWorkspacePrivacyRule,
        changedPaths: Set<String>,
        previousFinding: AIWorkspacePrivacyRuleFinding?
    ) -> Bool {
        for path in changedPaths {
            if ruleAffects(relativePath: path, rule: rule) {
                return true
            }
            if previousFinding?.matchedRelativePaths.contains(path) == true {
                return true
            }
        }
        return false
    }

    static func ruleAffects(relativePath: String, rule: AIWorkspacePrivacyRule) -> Bool {
        for pattern in rule.relativePathPatterns {
            if patternMatchesOrScopes(relativePath: relativePath, pattern: pattern) {
                return true
            }
        }
        return false
    }

    private static func patternMatchesOrScopes(relativePath: String, pattern: String) -> Bool {
        if pattern.contains("*") || pattern.contains("?") {
            if GlobPattern(pattern).matches(relativePath) {
                return true
            }
            let prefix = staticDirectoryPrefix(for: pattern)
            return path(prefix, isParentOrAncestorOf: relativePath)
                || path(relativePath, isParentOrAncestorOf: prefix)
        }

        if relativePath == pattern {
            return true
        }

        return path(relativePath, isParentOrAncestorOf: pattern)
            || path(pattern, isParentOrAncestorOf: relativePath)
    }
}
