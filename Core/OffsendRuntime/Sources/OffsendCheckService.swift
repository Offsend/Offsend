import DetectionCore
import DocumentCore
import Foundation
import MaskingCore
import RiskScoringCore
import WorkspacePolicyCore

public struct OffsendCheckRequest: Sendable {
    public let fileURLs: [URL]
    public let policyDirectoryURL: URL?
    public let failPolicy: CheckFailPolicy
    public let workingDirectory: URL
    public let excludePatterns: [String]
    public let disabledDetectors: Set<SensitiveEntityType>
    public let customDictionaries: [CustomDictionaryItem]

    public init(
        fileURLs: [URL],
        policyDirectoryURL: URL? = nil,
        failPolicy: CheckFailPolicy = .block,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        excludePatterns: [String] = [],
        disabledDetectors: Set<SensitiveEntityType> = [],
        customDictionaries: [CustomDictionaryItem] = []
    ) {
        self.fileURLs = fileURLs
        self.policyDirectoryURL = policyDirectoryURL
        self.failPolicy = failPolicy
        self.workingDirectory = workingDirectory
        self.excludePatterns = excludePatterns
        self.disabledDetectors = disabledDetectors
        self.customDictionaries = customDictionaries
    }
}

public struct OffsendTextCheckResult: Sendable {
    public let report: CheckReport
    public let entities: [SensitiveEntity]
    public let scannedText: String
    /// Opaque encoded candidates exceeded the bounded decode/scan budget.
    /// Agent-facing gates must deny/withhold rather than allow an unscanned tail.
    public let opaqueScanOverflow: Bool

    public init(
        report: CheckReport,
        entities: [SensitiveEntity],
        scannedText: String,
        opaqueScanOverflow: Bool = false
    ) {
        self.report = report
        self.entities = entities
        self.scannedText = scannedText
        self.opaqueScanOverflow = opaqueScanOverflow
    }
}

public struct OffsendCheckService: Sendable {
    private let context: OffsendRuntimeContext
    private let pipeline: DocumentProcessingPipeline
    private let auditor: AIWorkspacePrivacyAuditor
    private let detector: SensitiveDataDetecting
    private let riskScorer: RiskScoring
    private let defaultSealEngine: SealEngine?

    /// Resolved once per process: hook invocations build several services per
    /// run, and the default-key lookup can touch the filesystem/Keychain.
    private static let cachedDefaultSealEngine: SealEngine? = (try? SealKeyResolver.resolve(
        key: nil,
        keyFilePath: nil,
        keyName: nil
    ).data).flatMap { try? SealEngine(keyData: $0) }

    public init(
        context: OffsendRuntimeContext,
        pipeline: DocumentProcessingPipeline = DocumentProcessingPipeline.forRuntime(),
        auditor: AIWorkspacePrivacyAuditor = AIWorkspacePrivacyAuditor(),
        detector: SensitiveDataDetecting = DetectionEngine(),
        riskScorer: RiskScoring = RiskScoringEngine()
    ) {
        self.context = context
        self.pipeline = pipeline
        self.auditor = auditor
        self.detector = detector
        self.riskScorer = riskScorer
        self.defaultSealEngine = Self.cachedDefaultSealEngine
    }

    public func run(_ request: OffsendCheckRequest) async -> CheckReport {
        let options = OffsendConfiguration.documentProcessingOptions(
            context: context,
            disabledDetectors: request.disabledDetectors,
            additionalDictionaries: request.customDictionaries
        )

        let filteredURLs = PathExcludeMatcher.filter(
            fileURLs: request.fileURLs,
            excludePatterns: request.excludePatterns,
            workingDirectory: request.workingDirectory
        )

        let (fileFindings, fileIssues) = await scanFiles(
            filteredURLs,
            workingDirectory: request.workingDirectory,
            options: options
        )

        var policyFindings: [PolicyCheckFinding] = []
        if let policyDirectoryURL = request.policyDirectoryURL {
            let projectConfig = try? ProjectConfigLoader().load(from: policyDirectoryURL)
            let configuration = OffsendConfiguration.directoryCheckConfiguration(context: context)
                .filtered(tools: projectConfig?.ignore?.toolIDs)
            // With `.offsend.yml` present and `ignore.commit: false` (the default),
            // AI ignore files are gitignored and materialized locally by
            // `offsend sync`, so their absence (fresh clone, CI checkout)
            // is expected — not a policy failure.
            let managedFilesExpectedMissing = projectConfig != nil
                && !(projectConfig?.ignore?.commitsIgnoreFiles ?? false)
            policyFindings = makePolicyFindings(
                directoryURL: policyDirectoryURL,
                configuration: configuration,
                skipMissingManagedFiles: managedFilesExpectedMissing
            )
            if let patterns = projectConfig?.ignore?.patterns,
               !patterns.isEmpty {
                let drift = OffsendManagedIgnoreDrift.findings(
                    directoryURL: policyDirectoryURL,
                    patterns: patterns,
                    configuration: configuration
                )
                for item in drift {
                    // Fail (not warn): with `fail-on: block` (CI default), ignore drift
                    // must break the build — suggested per-editor rules otherwise drift silently.
                    policyFindings.append(
                        PolicyCheckFinding(
                            message: "Managed ignore drift in \(item.relativePath): missing \(item.missingPatterns.joined(separator: ", ")). Policy in .offsend.yml is ahead of this file. Run: offsend sync",
                            status: .fail
                        )
                    )
                }
                policyFindings.append(contentsOf: trackedIgnorePatternFindings(
                    directoryURL: policyDirectoryURL,
                    patterns: patterns
                ))
            }
            policyFindings.append(contentsOf: SandboxPolicyAudit.findings(
                repositoryURL: policyDirectoryURL,
                config: projectConfig
            ).map {
                PolicyCheckFinding(message: $0.message, status: $0.isFailure ? .fail : .warning)
            })
        }

        return CheckReport(
            fileFindings: fileFindings,
            fileIssues: fileIssues,
            policyFindings: policyFindings,
            failPolicy: request.failPolicy
        )
    }

    /// Scan a single in-memory prompt/text buffer (CLI `--stdin`).
    public func runText(
        _ text: String,
        failPolicy: CheckFailPolicy = .block,
        disabledDetectors: Set<SensitiveEntityType> = [],
        customDictionaries: [CustomDictionaryItem] = []
    ) async -> OffsendTextCheckResult {
        var detectionOptions = OffsendConfiguration.detectionOptions(
            context: context,
            enableAIDetection: false,
            disabledDetectors: disabledDetectors,
            additionalDictionaries: customDictionaries
        )
        // Prompt/clipboard-like input is untrusted: never honor inline ignore bypasses.
        detectionOptions.honorInlineIgnore = false

        let detection = await detector.scan(
            DetectionRequest(text: text, options: detectionOptions)
        )
        // `{{TYPE:v1.…}}` seal tokens are already-protected values; their
        // ciphertext bodies must not re-trigger detectors.
        var scannedEntities = filterSealTokenFindings(
            detection.entities,
            in: detection.scannedText
        )
        let opaqueScan = await opaqueEncodedSecretEntities(
            in: detection.scannedText,
            options: detectionOptions,
            existing: scannedEntities
        )
        scannedEntities.append(contentsOf: opaqueScan.entities)
        let assessment = riskScorer.assess(scannedEntities)
        let findings: [FileCheckFinding]
        if assessment.recommendedAction == .allow {
            findings = []
        } else {
            findings = scannedEntities.map { entity in
                FileCheckFinding(
                    relativePath: "<stdin>",
                    line: lineNumber(for: entity.range, in: detection.scannedText),
                    entityType: entity.type,
                    recommendedAction: action(for: entity, assessment: assessment),
                    hasCriticalSecret: entity.type.countsAsCriticalSecret
                )
            }
        }

        // When risk says allow, only surface secret-shaped entities for hook advice.
        let adviceEntities: [SensitiveEntity]
        if assessment.recommendedAction == .allow {
            adviceEntities = scannedEntities.filter(\.type.isSecret)
        } else {
            adviceEntities = scannedEntities
        }

        let report = CheckReport(
            fileFindings: findings,
            fileIssues: [],
            policyFindings: [],
            failPolicy: failPolicy
        )
        return OffsendTextCheckResult(
            report: report,
            entities: adviceEntities,
            scannedText: detection.scannedText,
            opaqueScanOverflow: opaqueScan.overflow
        )
    }

    /// Decode large base64/hex runs and re-scan the plaintext. When the decoded
    /// payload holds a critical secret, flag the encoded span in the source so
    /// read-gate deny/seal covers terminal exfil dumps.
    private func opaqueEncodedSecretEntities(
        in scannedText: String,
        options: DetectionOptions,
        existing: [SensitiveEntity]
    ) async -> (entities: [SensitiveEntity], overflow: Bool) {
        let extraction = OpaqueEncodedBlobExtractor.extract(in: scannedText)
        guard !extraction.blobs.isEmpty else {
            return ([], extraction.exceededSafetyBudget)
        }

        var extras: [SensitiveEntity] = []
        for blob in extraction.blobs {
            // Skip spans already covered by a critical plaintext hit. Fuzzy
            // `highEntropyString` on the encoded run itself must not block the
            // decode probe — that is the F2 exfil path.
            if existing.contains(where: {
                $0.range.overlaps(blob.range) && $0.type.countsAsCriticalSecret
            }) {
                continue
            }
            var nestedOptions = options
            // Decoded payloads are small; keep AI off and honorInlineIgnore false.
            nestedOptions.maximumLength = OpaqueEncodedBlobExtractor.maxDecodedBytes
            let nested = await detector.scan(
                DetectionRequest(text: blob.decodedUTF8, options: nestedOptions)
            )
            let critical = filterSealTokenFindings(nested.entities, in: nested.scannedText)
                .filter(\.type.countsAsCriticalSecret)
            guard let strongest = critical.max(by: { $0.confidence < $1.confidence }) else {
                continue
            }
            extras.append(
                SensitiveEntity(
                    type: strongest.type,
                    range: blob.range,
                    value: String(scannedText[blob.range]),
                    confidence: strongest.confidence,
                    source: .secret
                )
            )
        }
        return (extras, extraction.exceededSafetyBudget)
    }

    /// Scans files concurrently while keeping findings in the input order.
    private func scanFiles(
        _ fileURLs: [URL],
        workingDirectory: URL,
        options: DocumentProcessingOptions
    ) async -> (findings: [FileCheckFinding], issues: [FileCheckIssue]) {
        enum ScanResult {
            case findings([FileCheckFinding])
            case issue(FileCheckIssue)
        }

        let maxConcurrent = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
        var resultsByIndex: [Int: ScanResult] = [:]

        await withTaskGroup(of: (Int, ScanResult).self) { group in
            var nextIndex = 0

            func addTask(index: Int) {
                let fileURL = fileURLs[index]
                let relativePath = relativePath(for: fileURL, workingDirectory: workingDirectory)
                group.addTask {
                    do {
                        let analysisRequest = try DocumentProcessingRequest(
                            fileURL: fileURL.standardizedFileURL,
                            options: options
                        )
                        let analysis = try await pipeline.analyze(analysisRequest)
                        return (index, .findings(makeFindings(relativePath: relativePath, analysis: analysis)))
                    } catch let error as DocumentProcessingError {
                        return (index, .issue(FileCheckIssue(relativePath: relativePath, message: message(for: error))))
                    } catch {
                        return (index, .issue(FileCheckIssue(relativePath: relativePath, message: error.localizedDescription)))
                    }
                }
            }

            while nextIndex < min(maxConcurrent, fileURLs.count) {
                addTask(index: nextIndex)
                nextIndex += 1
            }

            for await (index, result) in group {
                resultsByIndex[index] = result
                if nextIndex < fileURLs.count {
                    addTask(index: nextIndex)
                    nextIndex += 1
                }
            }
        }

        var findings: [FileCheckFinding] = []
        var issues: [FileCheckIssue] = []
        for index in 0..<fileURLs.count {
            switch resultsByIndex[index] {
            case .findings(let fileFindings):
                findings.append(contentsOf: fileFindings)
            case .issue(let issue):
                issues.append(issue)
            case nil:
                break
            }
        }
        return (findings, issues)
    }

    private func makeFindings(
        relativePath: String,
        analysis: DocumentAnalysisResult
    ) -> [FileCheckFinding] {
        guard analysis.assessment.recommendedAction != .allow else { return [] }

        // Seal tokens in files (e.g. sealed copies) are not live secrets.
        let entities = filterSealTokenFindings(
            analysis.detection.entities,
            in: analysis.detection.scannedText
        )
        return entities.map { entity in
            FileCheckFinding(
                relativePath: relativePath,
                line: lineNumber(for: entity.range, in: analysis.detection.scannedText),
                entityType: entity.type,
                recommendedAction: action(for: entity, assessment: analysis.assessment),
                hasCriticalSecret: entity.type.countsAsCriticalSecret
            )
        }
    }

    private func filterSealTokenFindings(
        _ entities: [SensitiveEntity],
        in text: String
    ) -> [SensitiveEntity] {
        let syntacticallyFiltered = SealTokenDetector.excludingTokenSpans(entities, in: text)
        guard let defaultSealEngine else { return syntacticallyFiltered }
        return defaultSealEngine.excludingAuthenticatedTokenSpans(
            syntacticallyFiltered,
            in: text
        )
    }

    private func action(
        for entity: SensitiveEntity,
        assessment: RiskAssessment
    ) -> RecommendedAction {
        if entity.type.countsAsCriticalSecret {
            return .block
        }
        return assessment.recommendedAction
    }

    private func makePolicyFindings(
        directoryURL: URL,
        configuration: AIWorkspacePrivacyAuditConfiguration,
        skipMissingManagedFiles: Bool = false
    ) -> [PolicyCheckFinding] {
        let result = auditor.audit(directoryURL: directoryURL, configuration: configuration)
        var findings: [PolicyCheckFinding] = []

        for error in result.errors {
            findings.append(PolicyCheckFinding(message: error.message, status: .fail))
        }

        for finding in result.ruleFindings where !finding.isSatisfied {
            if skipMissingManagedFiles, finding.rule.isMaterializedByIgnoreSync {
                continue
            }
            let severity: AIWorkspacePrivacyAuditStatus = finding.rule.severity == .required ? .fail : .warning
            findings.append(
                PolicyCheckFinding(
                    message: "Missing \(finding.rule.toolName) ignore file (\(finding.rule.title))",
                    status: severity
                )
            )
        }

        for finding in result.sensitivePatternFindings where !finding.exposedRelativePaths.isEmpty {
            let paths = finding.exposedRelativePaths.prefix(3).joined(separator: ", ")
            let suffix = finding.exposedRelativePaths.count > 3 ? ", …" : ""
            findings.append(
                PolicyCheckFinding(
                    message: "Exposed sensitive paths: \(paths)\(suffix)",
                    status: .warning
                )
            )
        }

        if findings.isEmpty, result.status != .pass {
            // Suppress the fallback when the non-pass status comes only from
            // managed ignore files intentionally skipped above.
            let onlySkippedManagedFiles = skipMissingManagedFiles
                && result.ruleFindings.allSatisfy { $0.isSatisfied || $0.rule.isMaterializedByIgnoreSync }
                && result.sensitivePatternFindings.allSatisfy(\.isSatisfied)
            if !onlySkippedManagedFiles {
                findings.append(
                    PolicyCheckFinding(
                        message: "Workspace policy status: \(result.status.rawValue)",
                        status: result.status
                    )
                )
            }
        }

        return findings
    }

    /// Fail when `ignore.patterns` covers paths that git still tracks — local
    /// AI gates cannot protect bytes already public on origin (WebFetch / clone).
    private func trackedIgnorePatternFindings(
        directoryURL: URL,
        patterns: [String]
    ) -> [PolicyCheckFinding] {
        let resolver = GitRepositoryResolver()
        let repoRoot: URL
        do {
            repoRoot = try resolver.repositoryRoot(startingAt: directoryURL)
        } catch {
            return []
        }
        let tracked: [String]
        do {
            tracked = try resolver.allTrackedRelativePaths(in: repoRoot)
        } catch {
            return []
        }
        let hits = tracked.filter { path in
            IgnorePatternPathMatcher.isIgnored(relativePath: path, ignoreLines: patterns)
        }
        guard !hits.isEmpty else { return [] }
        let shown = hits.prefix(8).joined(separator: ", ")
        let suffix = hits.count > 8 ? " (+\(hits.count - 8) more)" : ""
        return [
            PolicyCheckFinding(
                message: "Git tracks paths covered by ignore.patterns: \(shown)\(suffix). "
                    + "Local AI gates cannot protect committed bytes (clone / raw.githubusercontent). "
                    + "Remove with `git rm --cached <path>`, keep secrets out of the default branch, and rotate if leaked.",
                status: .fail
            )
        ]
    }

    private func relativePath(for fileURL: URL, workingDirectory: URL) -> String {
        let standardizedFile = fileURL.standardizedFileURL
        let standardizedWorking = workingDirectory.standardizedFileURL
        let workingPath = standardizedWorking.path
        let filePath = standardizedFile.path

        if filePath.hasPrefix(workingPath + "/") {
            return String(filePath.dropFirst(workingPath.count + 1))
        }
        return standardizedFile.lastPathComponent
    }

    private func lineNumber(for range: Range<String.Index>, in text: String) -> Int {
        text[..<range.lowerBound].filter { $0 == "\n" }.count + 1
    }

    private func message(for error: DocumentProcessingError) -> String {
        switch error {
        case .unsupportedFormat(let fileExtension):
            return "Unsupported format (.\(fileExtension))"
        case .fileTooLarge(let byteCount, let maximumByteCount):
            return "File too large (\(byteCount) bytes, limit \(maximumByteCount))"
        case .emptyDocument:
            return "Empty file"
        case .invalidPDF:
            return "Invalid PDF"
        case .unreadableFile(let message):
            return "Unreadable file: \(message)"
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        }
    }
}
