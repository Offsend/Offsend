import Foundation

/// Detects on-disk files whose paths look sensitive and are not covered by effective
/// ignore rules. Reads ignore-file contents only; never inspects matched file bodies.
public final class SensitivePathExposureChecker: @unchecked Sendable {
    public static let builtInSkippedDirectoryNames: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData"
    ]

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Returns a finding when `relativePath` matches a sensitive pattern and no ignore
    /// line from `ignorePatternsByFile` covers it.
    public func exposedFinding(
        relativePath: String,
        sensitivePatterns: [AIWorkspaceSensitivePattern],
        ignorePatternsByFile: [String: Set<String>]
    ) -> AIWorkspaceExposedFileFinding? {
        guard !SensitivePathExposureAllowlist.isAllowlisted(relativePath: relativePath) else {
            return nil
        }

        guard let pattern = SensitivePathMatcher.matchingPattern(
            relativePath: relativePath,
            patterns: sensitivePatterns
        ) else {
            return nil
        }

        guard !IgnorePatternPathMatcher.isIgnored(
            relativePath: relativePath,
            ignorePatternsByFile: ignorePatternsByFile
        ) else {
            return nil
        }

        return AIWorkspaceExposedFileFinding(relativePath: relativePath, pattern: pattern)
    }

    public func matchesSensitivePattern(
        relativePath: String,
        sensitivePatterns: [AIWorkspaceSensitivePattern]
    ) -> Bool {
        guard !SensitivePathExposureAllowlist.isAllowlisted(relativePath: relativePath) else {
            return false
        }
        return SensitivePathMatcher.matchingPattern(relativePath: relativePath, patterns: sensitivePatterns) != nil
    }

    public func exposedAmong(
        relativePaths: some Sequence<String>,
        sensitivePatterns: [AIWorkspaceSensitivePattern],
        ignorePatternsByFile: [String: Set<String>]
    ) -> [AIWorkspaceExposedFileFinding] {
        var findings: [AIWorkspaceExposedFileFinding] = []
        var seenPaths = Set<String>()

        for relativePath in relativePaths {
            guard seenPaths.insert(relativePath).inserted else { continue }
            if let finding = exposedFinding(
                relativePath: relativePath,
                sensitivePatterns: sensitivePatterns,
                ignorePatternsByFile: ignorePatternsByFile
            ) {
                findings.append(finding)
            }
        }

        return findings.sorted { $0.relativePath < $1.relativePath }
    }

    /// Re-evaluates exposure for indexed paths after ignore rules change (no tree walk).
    public func exposedAmongIndexed(
        index: SensitivePathExposureIndex,
        sensitivePatterns: [AIWorkspaceSensitivePattern],
        ignorePatternsByFile: [String: Set<String>],
        rootURL: URL
    ) -> [AIWorkspaceExposedFileFinding] {
        exposedAmong(
            relativePaths: index.sensitiveRelativePaths.filter { path in
                fileManager.fileExists(atPath: rootURL.appendingPathComponent(path).path)
            },
            sensitivePatterns: sensitivePatterns,
            ignorePatternsByFile: ignorePatternsByFile
        )
    }

    public func updatedIndex(
        previousIndex: SensitivePathExposureIndex?,
        changedRelativePaths: Set<String>,
        sensitivePatterns: [AIWorkspaceSensitivePattern],
        rootURL: URL
    ) -> SensitivePathExposureIndex {
        var paths = previousIndex?.sensitiveRelativePaths ?? []

        for path in changedRelativePaths where !path.isEmpty {
            paths.remove(path)

            let fullURL = rootURL.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fullURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  matchesSensitivePattern(relativePath: path, sensitivePatterns: sensitivePatterns)
            else {
                continue
            }

            paths.insert(path)
        }

        return SensitivePathExposureIndex(sensitiveRelativePaths: paths)
    }

    /// Walks `directoryURL` (file names only, no content reads) and returns paths that
    /// match a sensitive pattern but are not ignored.
    public func scan(
        directoryURL: URL,
        sensitivePatterns: [AIWorkspaceSensitivePattern],
        ignorePatternsByFile: [String: Set<String>],
        skippedDirectoryNames: Set<String> = builtInSkippedDirectoryNames,
        limits: SensitivePathExposureScanLimits = .default,
        startedAt: Date = Date()
    ) -> SensitivePathExposureScanResult {
        let rootURL = directoryURL.standardizedFileURL
        guard isReadableDirectory(rootURL) else {
            return SensitivePathExposureScanResult(exposedFiles: [], completion: .complete)
        }

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else {
            return SensitivePathExposureScanResult(exposedFiles: [], completion: .complete)
        }

        let rootPrefix = rootURL.path + "/"
        var exposed: [AIWorkspaceExposedFileFinding] = []
        var indexedSensitivePaths = Set<String>()
        var filesScanned = 0
        var completion: SensitivePathExposureScanCompletion = .complete

        scanLoop: for case let item as URL in enumerator {
            if shouldSkipDescendants(of: item, skippedDirectoryNames: skippedDirectoryNames) {
                enumerator.skipDescendants()
                continue
            }

            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false else {
                continue
            }

            filesScanned += 1

            if let maxFiles = limits.maxFiles, filesScanned > maxFiles {
                completion = .truncated(maxFiles: maxFiles, filesScanned: filesScanned - 1)
                break scanLoop
            }

            if let timeLimit = limits.timeLimit,
               Date().timeIntervalSince(startedAt) > timeLimit {
                completion = .timedOut(timeLimit: timeLimit, filesScanned: filesScanned - 1)
                break scanLoop
            }

            let absolutePath = item.standardizedFileURL.path
            guard absolutePath.hasPrefix(rootPrefix) else { continue }
            let relativePath = String(absolutePath.dropFirst(rootPrefix.count))
            guard !relativePath.isEmpty else { continue }

            if isUnderSkippedDirectory(relativePath, skippedDirectoryNames: skippedDirectoryNames) {
                continue
            }

            if matchesSensitivePattern(relativePath: relativePath, sensitivePatterns: sensitivePatterns) {
                indexedSensitivePaths.insert(relativePath)
            }

            if let finding = exposedFinding(
                relativePath: relativePath,
                sensitivePatterns: sensitivePatterns,
                ignorePatternsByFile: ignorePatternsByFile
            ) {
                exposed.append(finding)
            }
        }

        return SensitivePathExposureScanResult(
            exposedFiles: exposed,
            indexedSensitivePaths: indexedSensitivePaths,
            filesScanned: filesScanned,
            completion: completion
        )
    }

    /// Loads ignore lines from the given ignore files under `rootURL`.
    public func loadIgnorePatterns(
        ignoreFileRelativePaths: [String],
        from rootURL: URL
    ) -> [String: Set<String>] {
        ignoreFileRelativePaths.reduce(into: [String: Set<String>]()) { result, relativePath in
            let url = rootURL.appendingPathComponent(relativePath)
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
            result[relativePath] = IgnoreFileParser.patterns(in: contents)
        }
    }

    /// Convenience scan: discovers ignore files from scan-enabled rules, loads their
    /// patterns, then walks the tree for exposed sensitive paths.
    public func scan(
        directoryURL: URL,
        configuration: AIWorkspacePrivacyAuditConfiguration
    ) -> SensitivePathExposureScanResult {
        let rootURL = directoryURL.standardizedFileURL
        let skippedDirectoryNames = Self.builtInSkippedDirectoryNames
            .union(configuration.additionalSkippedDirectoryNames)

        let ignoreFilePaths = configuration.rules
            .filter(\.scansForSensitivePatterns)
            .flatMap(\.relativePathPatterns)
            .filter { !$0.contains("*") && !$0.contains("?") }

        let ignorePatternsByFile = loadIgnorePatterns(
            ignoreFileRelativePaths: Array(Set(ignoreFilePaths)).sorted(),
            from: rootURL
        )

        return scan(
            directoryURL: rootURL,
            sensitivePatterns: configuration.sensitivePatterns,
            ignorePatternsByFile: ignorePatternsByFile,
            skippedDirectoryNames: skippedDirectoryNames,
            limits: configuration.exposureScanLimits
        )
    }

    private func isReadableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return fileManager.isReadableFile(atPath: url.path)
    }

    private func shouldSkipDescendants(of url: URL, skippedDirectoryNames: Set<String>) -> Bool {
        guard skippedDirectoryNames.contains(url.lastPathComponent),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
            return false
        }
        return true
    }

    private func isUnderSkippedDirectory(_ relativePath: String, skippedDirectoryNames: Set<String>) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        return components.contains(where: skippedDirectoryNames.contains)
    }
}
