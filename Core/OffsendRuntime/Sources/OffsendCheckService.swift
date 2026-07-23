import DetectionCore
import DocumentCore
import Foundation
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

    public init(report: CheckReport, entities: [SensitiveEntity], scannedText: String) {
        self.report = report
        self.entities = entities
        self.scannedText = scannedText
    }
}

public struct OffsendCheckService: Sendable {
    private let context: OffsendRuntimeContext
    private let pipeline: DocumentProcessingPipeline
    private let auditor: AIWorkspacePrivacyAuditor
    private let detector: SensitiveDataDetecting
    private let riskScorer: RiskScoring

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
            }
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
        let assessment = riskScorer.assess(detection.entities)
        let findings: [FileCheckFinding]
        if assessment.recommendedAction == .allow {
            findings = []
        } else {
            findings = detection.entities.map { entity in
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
            adviceEntities = detection.entities.filter(\.type.isSecret)
        } else {
            adviceEntities = detection.entities
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
            scannedText: detection.scannedText
        )
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

        return analysis.detection.entities.map { entity in
            FileCheckFinding(
                relativePath: relativePath,
                line: lineNumber(for: entity.range, in: analysis.detection.scannedText),
                entityType: entity.type,
                recommendedAction: action(for: entity, assessment: analysis.assessment),
                hasCriticalSecret: entity.type.countsAsCriticalSecret
            )
        }
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
