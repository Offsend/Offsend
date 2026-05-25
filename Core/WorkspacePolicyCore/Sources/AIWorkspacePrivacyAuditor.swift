import Foundation

public final class AIWorkspacePrivacyAuditor {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func audit(
        directoryURL: URL,
        configuration: AIWorkspacePrivacyAuditConfiguration = .default
    ) -> AIWorkspacePrivacyAuditResult {
        let standardizedURL = directoryURL.standardizedFileURL
        guard isReadableDirectory(standardizedURL) else {
            return AIWorkspacePrivacyAuditResult(
                directoryURL: standardizedURL,
                status: .fail,
                ruleFindings: [],
                sensitivePatternFindings: [],
                errors: [
                    AIWorkspacePrivacyAuditError(
                        id: "directory-unavailable",
                        message: "The selected path is not a readable directory."
                    )
                ]
            )
        }

        let skippedDirectoryNames = Self.builtInSkippedDirectoryNames
            .union(configuration.additionalSkippedDirectoryNames)

        let ruleFindings = configuration.rules.map { rule in
            AIWorkspacePrivacyRuleFinding(
                rule: rule,
                matchedRelativePaths: matchedRelativePaths(
                    for: rule,
                    in: standardizedURL,
                    skippedDirectoryNames: skippedDirectoryNames
                )
            )
        }

        let ignoreFilePaths = ruleFindings
            .filter { $0.rule.scansForSensitivePatterns }
            .flatMap(\.matchedRelativePaths)
        let ignorePatterns = loadIgnorePatterns(ignoreFilePaths, from: standardizedURL)
        let sensitiveFindings = configuration.sensitivePatterns.map { pattern in
            AIWorkspaceSensitivePatternFinding(
                pattern: pattern,
                matchedIgnoreFilePaths: matchingIgnoreFiles(for: pattern, in: ignorePatterns)
            )
        }

        return AIWorkspacePrivacyAuditResult(
            directoryURL: standardizedURL,
            status: status(ruleFindings: ruleFindings, sensitiveFindings: sensitiveFindings),
            ruleFindings: ruleFindings,
            sensitivePatternFindings: sensitiveFindings,
            errors: []
        )
    }

    private func isReadableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return fileManager.isReadableFile(atPath: url.path)
    }

    private func matchedRelativePaths(
        for rule: AIWorkspacePrivacyRule,
        in rootURL: URL,
        skippedDirectoryNames: Set<String>
    ) -> [String] {
        let matches = rule.relativePathPatterns.flatMap { pattern -> [String] in
            if pattern.contains("*") || pattern.contains("?") {
                return globMatches(pattern: pattern, in: rootURL, skippedDirectoryNames: skippedDirectoryNames)
            }

            let candidate = rootURL.appendingPathComponent(pattern)
            return fileManager.fileExists(atPath: candidate.path) ? [pattern] : []
        }

        return Array(Set(matches)).sorted()
    }

    private func globMatches(
        pattern: String,
        in rootURL: URL,
        skippedDirectoryNames: Set<String>
    ) -> [String] {
        let baseRelativePath = Self.staticDirectoryPrefix(for: pattern)
        let searchRootURL = baseRelativePath.isEmpty ? rootURL : rootURL.appendingPathComponent(baseRelativePath)
        if let directMatches = directChildGlobMatches(pattern: pattern, baseRelativePath: baseRelativePath, searchRootURL: searchRootURL) {
            return directMatches
        }

        guard let enumerator = fileManager.enumerator(
            at: searchRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        let glob = GlobPattern(pattern)
        return enumerator.compactMap { item -> String? in
            guard let url = item as? URL else { return nil }
            if shouldSkipDescendants(of: url, skippedDirectoryNames: skippedDirectoryNames) {
                enumerator.skipDescendants()
                return nil
            }
            let pathFromSearchRoot = url.path.replacingOccurrences(of: searchRootURL.path + "/", with: "")
            let relativePath = baseRelativePath.isEmpty ? pathFromSearchRoot : "\(baseRelativePath)/\(pathFromSearchRoot)"
            return glob.matches(relativePath) ? relativePath : nil
        }
    }

    private func directChildGlobMatches(
        pattern: String,
        baseRelativePath: String,
        searchRootURL: URL
    ) -> [String]? {
        let searchSuffix = baseRelativePath.isEmpty ? pattern : String(pattern.dropFirst(baseRelativePath.count + 1))
        guard !searchSuffix.contains("/") else { return nil }
        guard let childNames = try? fileManager.contentsOfDirectory(atPath: searchRootURL.path) else { return [] }

        let glob = GlobPattern(pattern)
        return childNames.compactMap { childName in
            let relativePath = baseRelativePath.isEmpty ? childName : "\(baseRelativePath)/\(childName)"
            return glob.matches(relativePath) ? relativePath : nil
        }
        .sorted()
    }

    private static func staticDirectoryPrefix(for pattern: String) -> String {
        guard let wildcardIndex = pattern.firstIndex(where: { $0 == "*" || $0 == "?" }) else {
            return pattern
        }
        let prefix = pattern[..<wildcardIndex]
        guard let slashIndex = prefix.lastIndex(of: "/") else { return "" }
        return String(prefix[..<slashIndex])
    }

    static let builtInSkippedDirectoryNames: Set<String> = [".git", "node_modules", ".build", "DerivedData"]

    private func shouldSkipDescendants(of url: URL, skippedDirectoryNames: Set<String>) -> Bool {
        guard skippedDirectoryNames.contains(url.lastPathComponent),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
            return false
        }
        return true
    }

    private func loadIgnorePatterns(_ relativePaths: [String], from rootURL: URL) -> [String: Set<String>] {
        relativePaths.reduce(into: [String: Set<String>]()) { result, relativePath in
            let url = rootURL.appendingPathComponent(relativePath)
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
            result[relativePath] = IgnoreFileParser.patterns(in: contents)
        }
    }

    private func matchingIgnoreFiles(
        for pattern: AIWorkspaceSensitivePattern,
        in ignorePatterns: [String: Set<String>]
    ) -> [String] {
        ignorePatterns.compactMap { relativePath, patterns in
            patterns.contains { candidate in
                pattern.acceptedPatterns.contains { accepted in
                    candidate == accepted || GlobPattern(accepted).matches(candidate)
                }
            } ? relativePath : nil
        }
        .sorted()
    }

    private func status(
        ruleFindings: [AIWorkspacePrivacyRuleFinding],
        sensitiveFindings: [AIWorkspaceSensitivePatternFinding]
    ) -> AIWorkspacePrivacyAuditStatus {
        if ruleFindings.contains(where: { !$0.isSatisfied && $0.rule.severity == .required }) {
            return .fail
        }
        if sensitiveFindings.contains(where: { !$0.isSatisfied && $0.pattern.severity == .required }) {
            return .fail
        }
        if ruleFindings.contains(where: { !$0.isSatisfied && $0.rule.severity == .recommended }) {
            return .warning
        }
        if sensitiveFindings.contains(where: { !$0.isSatisfied && $0.pattern.severity == .recommended }) {
            return .warning
        }
        return .pass
    }
}
