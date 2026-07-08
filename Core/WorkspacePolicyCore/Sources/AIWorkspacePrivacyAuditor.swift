import Foundation

/// Audits a workspace for AI privacy policy files and whether on-disk paths that
/// match curated sensitive patterns are covered by effective ignore rules.
///
/// Rule findings still check for the presence of expected ignore files. Sensitive
/// pattern findings are exposure-based: a pattern is reported only when matching
/// files exist on disk and are not ignored. Reading file contents is limited to
/// ignore policy files, not matched sensitive paths.
public final class AIWorkspacePrivacyAuditor: @unchecked Sendable {
    private let fileManager: FileManager
    private let exposureChecker: SensitivePathExposureChecker

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.exposureChecker = SensitivePathExposureChecker(fileManager: fileManager)
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

        let exposureState = sensitiveExposureState(
            configuration: configuration,
            ruleFindings: ruleFindings,
            rootURL: standardizedURL,
            skippedDirectoryNames: skippedDirectoryNames
        )
        let ignorePatterns = exposureState.ignorePatterns
        let ruleFindingsWithExposure = ruleFindingsWithPerToolExposure(
            ruleFindings: ruleFindings,
            exposureIndex: exposureState.index,
            sensitivePatterns: configuration.sensitivePatterns,
            ignorePatterns: ignorePatterns,
            rootURL: standardizedURL
        )
        let sensitiveFindings = aggregatedSensitiveFindings(
            configuration: configuration,
            ruleFindings: ruleFindingsWithExposure,
            ignorePatterns: ignorePatterns,
            baselineFindings: exposureState.sensitiveFindings
        )

        let baseStatus = status(
            ruleFindings: ruleFindingsWithExposure,
            sensitiveFindings: sensitiveFindings
        )
        let (finalStatus, errors) = applyExposureScanCompletion(
            baseStatus: baseStatus,
            completion: exposureState.scanCompletion,
            existingErrors: exposureState.errors
        )

        return AIWorkspacePrivacyAuditResult(
            directoryURL: standardizedURL,
            status: finalStatus,
            ruleFindings: ruleFindingsWithExposure,
            sensitivePatternFindings: sensitiveFindings,
            errors: errors,
            exposureIndex: exposureState.index,
            exposureScanCompletion: exposureState.scanCompletion
        )
    }

    public func auditDelta(
        directoryURL: URL,
        changedRelativePaths: Set<String>,
        previousResult: AIWorkspacePrivacyAuditResult,
        configuration: AIWorkspacePrivacyAuditConfiguration = .default
    ) -> AIWorkspacePrivacyAuditResult? {
        let standardizedURL = directoryURL.standardizedFileURL
        guard isReadableDirectory(standardizedURL) else { return nil }
        guard !changedRelativePaths.isEmpty else { return nil }
        guard previousResult.directoryURL.standardizedFileURL == standardizedURL else { return nil }

        // The incremental path reuses findings from `previousResult`. If the rule or
        // sensitive-pattern set changed since then (e.g. Free↔Pro, a disabled rule),
        // the delta would carry stale findings, so fall back to a full audit.
        let previousRuleIDs = Set(previousResult.ruleFindings.map(\.rule.id))
        let previousPatternIDs = Set(previousResult.sensitivePatternFindings.map(\.pattern.id))
        guard previousRuleIDs == Set(configuration.rules.map(\.id)),
              previousPatternIDs == Set(configuration.sensitivePatterns.map(\.id))
        else {
            return audit(directoryURL: standardizedURL, configuration: configuration)
        }

        let skippedDirectoryNames = Self.builtInSkippedDirectoryNames
            .union(configuration.additionalSkippedDirectoryNames)

        let previousRules = Dictionary(uniqueKeysWithValues: previousResult.ruleFindings.map { ($0.rule.id, $0) })
        var updatedRuleFindings = previousResult.ruleFindings

        for index in updatedRuleFindings.indices {
            let rule = updatedRuleFindings[index].rule
            guard configuration.rules.contains(where: { $0.id == rule.id }) else { continue }
            guard WorkspaceWatchPathMatching.ruleIsAffected(
                rule: rule,
                changedPaths: changedRelativePaths,
                previousFinding: previousRules[rule.id]
            ) else {
                continue
            }

            updatedRuleFindings[index] = updateRuleFinding(
                rule: rule,
                changedPaths: changedRelativePaths,
                previous: updatedRuleFindings[index],
                rootURL: standardizedURL,
                skippedDirectoryNames: skippedDirectoryNames
            )
        }

        let exposureState = sensitiveExposureState(
            configuration: configuration,
            ruleFindings: updatedRuleFindings,
            rootURL: standardizedURL,
            skippedDirectoryNames: skippedDirectoryNames,
            changedRelativePaths: changedRelativePaths,
            previousFindings: previousResult.sensitivePatternFindings,
            previousExposureIndex: previousResult.exposureIndex,
            previousExposureScanCompletion: previousResult.exposureScanCompletion
        )
        let ignorePatterns = exposureState.ignorePatterns
        let ruleFindingsWithExposure = ruleFindingsWithPerToolExposure(
            ruleFindings: updatedRuleFindings,
            exposureIndex: exposureState.index,
            sensitivePatterns: configuration.sensitivePatterns,
            ignorePatterns: ignorePatterns,
            rootURL: standardizedURL
        )
        let sensitiveFindings = aggregatedSensitiveFindings(
            configuration: configuration,
            ruleFindings: ruleFindingsWithExposure,
            ignorePatterns: ignorePatterns,
            baselineFindings: exposureState.sensitiveFindings
        )

        let baseStatus = status(
            ruleFindings: ruleFindingsWithExposure,
            sensitiveFindings: sensitiveFindings
        )
        let (finalStatus, errors) = applyExposureScanCompletion(
            baseStatus: baseStatus,
            completion: exposureState.scanCompletion,
            existingErrors: exposureState.errors
        )

        return AIWorkspacePrivacyAuditResult(
            directoryURL: standardizedURL,
            status: finalStatus,
            ruleFindings: ruleFindingsWithExposure,
            sensitivePatternFindings: sensitiveFindings,
            errors: errors,
            exposureIndex: exposureState.index,
            exposureScanCompletion: exposureState.scanCompletion
        )
    }

    private struct SensitiveExposureState {
        let sensitiveFindings: [AIWorkspaceSensitivePatternFinding]
        let index: SensitivePathExposureIndex?
        let scanCompletion: SensitivePathExposureScanCompletion
        let errors: [AIWorkspacePrivacyAuditError]
        /// Ignore-file patterns loaded during this pass, reused by the caller so ignore
        /// files are read from disk only once per audit.
        let ignorePatterns: [String: Set<String>]
    }

    private func sensitiveExposureState(
        configuration: AIWorkspacePrivacyAuditConfiguration,
        ruleFindings: [AIWorkspacePrivacyRuleFinding],
        rootURL: URL,
        skippedDirectoryNames: Set<String>,
        changedRelativePaths: Set<String>? = nil,
        previousFindings: [AIWorkspaceSensitivePatternFinding]? = nil,
        previousExposureIndex: SensitivePathExposureIndex? = nil,
        previousExposureScanCompletion: SensitivePathExposureScanCompletion = .complete
    ) -> SensitiveExposureState {
        let ignoreFilePaths = ruleFindings
            .filter { $0.rule.scansForSensitivePatterns }
            .flatMap(\.matchedRelativePaths)
        let ignorePatterns = loadIgnorePatterns(ignoreFilePaths, from: rootURL)
        let ignoreFilePathSet = Set(ignoreFilePaths)

        let exposedFiles: [AIWorkspaceExposedFileFinding]
        let index: SensitivePathExposureIndex?
        let scanCompletion: SensitivePathExposureScanCompletion

        if let changedRelativePaths,
           previousFindings != nil,
           shouldRescanAllExposure(
               changedRelativePaths: changedRelativePaths,
               ignoreFilePaths: ignoreFilePathSet
           ),
           let previousExposureIndex,
           previousExposureScanCompletion.isComplete {
            exposedFiles = exposureChecker.exposedAmongIndexed(
                index: previousExposureIndex,
                sensitivePatterns: configuration.sensitivePatterns,
                ignorePatternsByFile: ignorePatterns,
                rootURL: rootURL
            )
            index = previousExposureIndex
            scanCompletion = .complete
        } else if let changedRelativePaths, let previousFindings,
                  !shouldRescanAllExposure(
                      changedRelativePaths: changedRelativePaths,
                      ignoreFilePaths: ignoreFilePathSet
                  ) {
            index = exposureChecker.updatedIndex(
                previousIndex: previousExposureIndex,
                changedRelativePaths: changedRelativePaths,
                sensitivePatterns: configuration.sensitivePatterns,
                rootURL: rootURL
            )
            exposedFiles = incrementallyUpdateExposure(
                changedRelativePaths: changedRelativePaths,
                previousFindings: previousFindings,
                sensitivePatterns: configuration.sensitivePatterns,
                ignorePatternsByFile: ignorePatterns,
                rootURL: rootURL
            )
            scanCompletion = previousExposureScanCompletion
        } else {
            let scanResult = exposureChecker.scan(
                directoryURL: rootURL,
                sensitivePatterns: configuration.sensitivePatterns,
                ignorePatternsByFile: ignorePatterns,
                skippedDirectoryNames: skippedDirectoryNames,
                limits: configuration.exposureScanLimits
            )
            exposedFiles = scanResult.exposedFiles
            scanCompletion = scanResult.completion
            if scanResult.completion.isComplete {
                index = SensitivePathExposureIndex(
                    sensitiveRelativePaths: scanResult.indexedSensitivePaths
                )
            } else if let previousExposureIndex {
                index = previousExposureIndex.merging(scanResult.indexedSensitivePaths)
            } else {
                index = SensitivePathExposureIndex(
                    sensitiveRelativePaths: scanResult.indexedSensitivePaths
                )
            }
        }

        let exposedByPatternID = Dictionary(grouping: exposedFiles, by: { $0.pattern.id })
        let sensitiveFindings = configuration.sensitivePatterns.map { pattern in
            AIWorkspaceSensitivePatternFinding(
                pattern: pattern,
                matchedIgnoreFilePaths: matchingIgnoreFiles(for: pattern, in: ignorePatterns),
                exposedRelativePaths: exposedByPatternID[pattern.id]?.map(\.relativePath).sorted() ?? []
            )
        }

        let errors = scanCompletion.isComplete ? [] : [exposureScanIncompleteError(completion: scanCompletion)]

        return SensitiveExposureState(
            sensitiveFindings: sensitiveFindings,
            index: index,
            scanCompletion: scanCompletion,
            errors: errors,
            ignorePatterns: ignorePatterns
        )
    }

    private func applyExposureScanCompletion(
        baseStatus: AIWorkspacePrivacyAuditStatus,
        completion: SensitivePathExposureScanCompletion,
        existingErrors: [AIWorkspacePrivacyAuditError]
    ) -> (AIWorkspacePrivacyAuditStatus, [AIWorkspacePrivacyAuditError]) {
        guard !completion.isComplete else {
            return (baseStatus, existingErrors)
        }

        let status: AIWorkspacePrivacyAuditStatus
        switch baseStatus {
        case .pass:
            status = .warning
        case .warning, .fail:
            status = baseStatus
        }

        return (status, existingErrors)
    }

    private func exposureScanIncompleteError(
        completion: SensitivePathExposureScanCompletion
    ) -> AIWorkspacePrivacyAuditError {
        let message: String
        switch completion {
        case .complete:
            message = "Exposure scan did not complete."
        case let .truncated(maxFiles, filesScanned):
            message = "Exposure scan stopped after \(filesScanned) files (limit: \(maxFiles)). Results may be incomplete."
        case let .timedOut(timeLimit, filesScanned):
            message = "Exposure scan timed out after \(Int(timeLimit))s (\(filesScanned) files scanned). Results may be incomplete."
        }

        return AIWorkspacePrivacyAuditError(id: "exposure-scan-incomplete", message: message)
    }

    private func shouldRescanAllExposure(
        changedRelativePaths: Set<String>,
        ignoreFilePaths: Set<String>
    ) -> Bool {
        changedRelativePaths.contains("") || !changedRelativePaths.isDisjoint(with: ignoreFilePaths)
    }

    private func incrementallyUpdateExposure(
        changedRelativePaths: Set<String>,
        previousFindings: [AIWorkspaceSensitivePatternFinding],
        sensitivePatterns: [AIWorkspaceSensitivePattern],
        ignorePatternsByFile: [String: Set<String>],
        rootURL: URL
    ) -> [AIWorkspaceExposedFileFinding] {
        let patternsByID = Dictionary(uniqueKeysWithValues: sensitivePatterns.map { ($0.id, $0) })
        var exposedByPatternID: [String: Set<String>] = Dictionary(
            uniqueKeysWithValues: previousFindings.map { ($0.pattern.id, Set($0.exposedRelativePaths)) }
        )

        for path in changedRelativePaths where !path.isEmpty {
            for patternID in exposedByPatternID.keys {
                exposedByPatternID[patternID]?.remove(path)
            }

            let fullURL = rootURL.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fullURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                continue
            }

            if let finding = exposureChecker.exposedFinding(
                relativePath: path,
                sensitivePatterns: sensitivePatterns,
                ignorePatternsByFile: ignorePatternsByFile
            ) {
                exposedByPatternID[finding.pattern.id, default: []].insert(path)
            }
        }

        return exposedByPatternID.flatMap { patternID, paths in
            guard let pattern = patternsByID[patternID] else { return [AIWorkspaceExposedFileFinding]() }
            return paths.map { AIWorkspaceExposedFileFinding(relativePath: $0, pattern: pattern) }
        }
    }

    private func updateRuleFinding(
        rule: AIWorkspacePrivacyRule,
        changedPaths: Set<String>,
        previous: AIWorkspacePrivacyRuleFinding,
        rootURL: URL,
        skippedDirectoryNames: Set<String>
    ) -> AIWorkspacePrivacyRuleFinding {
        let hasGlobPatterns = rule.relativePathPatterns.contains { $0.contains("*") || $0.contains("?") }
        if hasGlobPatterns {
            let recomputed = matchedRelativePaths(
                for: rule,
                in: rootURL,
                skippedDirectoryNames: skippedDirectoryNames
            )
            return AIWorkspacePrivacyRuleFinding(rule: rule, matchedRelativePaths: recomputed)
        }

        var matched = Set(previous.matchedRelativePaths)

        for path in changedPaths {
            let fullPath = rootURL.appendingPathComponent(path).path
            if matched.contains(path) {
                if !fileManager.fileExists(atPath: fullPath)
                    || !WorkspaceWatchPathMatching.pathMatchesRule(
                        path,
                        rule: rule,
                        skippedDirectoryNames: skippedDirectoryNames
                    ) {
                    matched.remove(path)
                }
            } else if WorkspaceWatchPathMatching.pathMatchesRule(
                path,
                rule: rule,
                skippedDirectoryNames: skippedDirectoryNames
            ), fileManager.fileExists(atPath: fullPath) {
                matched.insert(path)
            }
        }

        return AIWorkspacePrivacyRuleFinding(
            rule: rule,
            matchedRelativePaths: Array(matched).sorted()
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
        let baseRelativePath = WorkspaceWatchPathMatching.staticDirectoryPrefix(for: pattern)
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
            let searchRootPrefix = searchRootURL.path + "/"
            let pathFromSearchRoot = url.path.hasPrefix(searchRootPrefix)
                ? String(url.path.dropFirst(searchRootPrefix.count))
                : url.path
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

    static let builtInSkippedDirectoryNames: Set<String> = SensitivePathExposureChecker.builtInSkippedDirectoryNames

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
        // Informational only: which ignore files declare an accepted form of this pattern.
        let accepted = Set(pattern.acceptedPatterns.map(Self.normalizedCoverageForm))
        return ignorePatterns.compactMap { relativePath, patterns in
            let normalized = Set(patterns.map(Self.normalizedCoverageForm))
            return normalized.isDisjoint(with: accepted) ? nil : relativePath
        }
        .sorted()
    }

    private static func normalizedCoverageForm(_ pattern: String) -> String {
        pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
    }

    private func ruleFindingsWithPerToolExposure(
        ruleFindings: [AIWorkspacePrivacyRuleFinding],
        exposureIndex: SensitivePathExposureIndex?,
        sensitivePatterns: [AIWorkspaceSensitivePattern],
        ignorePatterns: [String: Set<String>],
        rootURL: URL
    ) -> [AIWorkspacePrivacyRuleFinding] {
        guard let exposureIndex else {
            return ruleFindings
        }

        return ruleFindings.map { finding in
            guard finding.rule.scansForSensitivePatterns else {
                return finding
            }

            var exposed = Set<String>()
            if finding.matchedRelativePaths.isEmpty {
                guard finding.rule.severity == .required else {
                    return finding
                }
                exposed = Set(
                    exposureChecker.exposedAmongIndexed(
                        index: exposureIndex,
                        sensitivePatterns: sensitivePatterns,
                        ignorePatternsByFile: [:],
                        rootURL: rootURL
                    ).map(\.relativePath)
                )
            } else {
                for ignorePath in finding.matchedRelativePaths {
                    let perFilePatterns = [ignorePath: ignorePatterns[ignorePath] ?? []]
                    let fileExposed = exposureChecker.exposedAmongIndexed(
                        index: exposureIndex,
                        sensitivePatterns: sensitivePatterns,
                        ignorePatternsByFile: perFilePatterns,
                        rootURL: rootURL
                    )
                    exposed.formUnion(fileExposed.map(\.relativePath))
                }
            }

            return AIWorkspacePrivacyRuleFinding(
                rule: finding.rule,
                matchedRelativePaths: finding.matchedRelativePaths,
                exposedRelativePaths: exposed.sorted()
            )
        }
    }

    private func aggregatedSensitiveFindings(
        configuration: AIWorkspacePrivacyAuditConfiguration,
        ruleFindings: [AIWorkspacePrivacyRuleFinding],
        ignorePatterns: [String: Set<String>],
        baselineFindings: [AIWorkspaceSensitivePatternFinding]
    ) -> [AIWorkspaceSensitivePatternFinding] {
        let baselineByID = Dictionary(uniqueKeysWithValues: baselineFindings.map { ($0.pattern.id, $0) })
        let hasScanningIgnoreFiles = ruleFindings.contains {
            $0.rule.scansForSensitivePatterns && !$0.matchedRelativePaths.isEmpty
        }

        guard hasScanningIgnoreFiles else {
            return baselineFindings
        }

        return configuration.sensitivePatterns.map { pattern in
            let baseline = baselineByID[pattern.id]
            var exposed = Set<String>()
            for finding in ruleFindings where finding.rule.scansForSensitivePatterns {
                for path in finding.exposedRelativePaths where SensitivePathMatcher.matchingPattern(
                    relativePath: path,
                    patterns: [pattern]
                ) != nil {
                    exposed.insert(path)
                }
            }

            return AIWorkspaceSensitivePatternFinding(
                pattern: pattern,
                matchedIgnoreFilePaths: baseline?.matchedIgnoreFilePaths
                    ?? matchingIgnoreFiles(for: pattern, in: ignorePatterns),
                exposedRelativePaths: exposed.sorted()
            )
        }
    }

    private func status(
        ruleFindings: [AIWorkspacePrivacyRuleFinding],
        sensitiveFindings: [AIWorkspaceSensitivePatternFinding]
    ) -> AIWorkspacePrivacyAuditStatus {
        let hasRequiredExposure = sensitiveFindings.contains {
            !$0.isSatisfied && $0.pattern.severity == .required
        }
        let hasRequiredRuleExposure = ruleFindings.contains {
            !$0.exposedRelativePaths.isEmpty && $0.rule.severity == .required
        }
        if hasRequiredExposure || hasRequiredRuleExposure {
            return .fail
        }

        if ruleFindings.contains(where: { !$0.isSatisfied && $0.rule.severity == .required }) {
            return .warning
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
