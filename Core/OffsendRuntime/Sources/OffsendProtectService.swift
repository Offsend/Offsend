import Foundation
import WorkspacePolicyCore

/// Result of `offsend protect`: ensure AI ignore files exist, promote required
/// exposures into `.offsend.yml`, then sync the managed ignore boundary.
public struct ProtectReport: Sendable, Equatable {
    public let directoryPath: String
    public let dryRun: Bool
    public let includeRecommended: Bool
    /// Canonical ignore lines applied (or planned).
    public let patterns: [String]
    public let prepare: PrepareReport
    public let ignore: IgnoreReport?
    public let sync: IgnoreSyncReport?
    public let addedToConfig: [String]
    /// Exposed required paths remaining after the run (0 when dry-run skipped re-audit writes).
    public let remainingRequiredCount: Int
    public let remainingRecommendedCount: Int
    public let scanIncomplete: Bool
    public let errors: [String]

    public init(
        directoryPath: String,
        dryRun: Bool,
        includeRecommended: Bool,
        patterns: [String],
        prepare: PrepareReport,
        ignore: IgnoreReport?,
        sync: IgnoreSyncReport? = nil,
        addedToConfig: [String] = [],
        remainingRequiredCount: Int,
        remainingRecommendedCount: Int,
        scanIncomplete: Bool,
        errors: [String]
    ) {
        self.directoryPath = directoryPath
        self.dryRun = dryRun
        self.includeRecommended = includeRecommended
        self.patterns = patterns
        self.prepare = prepare
        self.ignore = ignore
        self.sync = sync
        self.addedToConfig = addedToConfig
        self.remainingRequiredCount = remainingRequiredCount
        self.remainingRecommendedCount = remainingRecommendedCount
        self.scanIncomplete = scanIncomplete
        self.errors = errors
    }

    public var hasErrors: Bool {
        !errors.isEmpty || prepare.hasErrors || (ignore?.hasErrors ?? false) || (sync?.hasErrors ?? false)
    }
}

/// Creates missing AI ignore files, promotes exposed sensitive patterns into
/// `ignore.patterns`, then materializes them via sync.
public struct OffsendProtectService: Sendable {
    private let configuration: AIWorkspacePrivacyAuditConfiguration
    private let auditor: AIWorkspacePrivacyAuditor
    private let prepareService: OffsendPrepareService
    private let ignoreService: OffsendIgnoreService
    private let syncService: OffsendIgnoreSyncService
    private let configLoader: ProjectConfigLoader

    public init(
        context: OffsendRuntimeContext,
        auditor: AIWorkspacePrivacyAuditor = AIWorkspacePrivacyAuditor()
    ) {
        let configuration = OffsendConfiguration.directoryCheckConfiguration(context: context)
        self.init(
            configuration: configuration,
            auditor: auditor,
            prepareService: OffsendPrepareService(configuration: configuration),
            ignoreService: OffsendIgnoreService(configuration: configuration),
            syncService: OffsendIgnoreSyncService(configuration: configuration),
            configLoader: ProjectConfigLoader()
        )
    }

    public init(
        configuration: AIWorkspacePrivacyAuditConfiguration,
        auditor: AIWorkspacePrivacyAuditor = AIWorkspacePrivacyAuditor(),
        prepareService: OffsendPrepareService? = nil,
        ignoreService: OffsendIgnoreService? = nil,
        syncService: OffsendIgnoreSyncService? = nil,
        configLoader: ProjectConfigLoader = ProjectConfigLoader()
    ) {
        self.configuration = configuration
        self.auditor = auditor
        self.prepareService = prepareService ?? OffsendPrepareService(configuration: configuration)
        self.ignoreService = ignoreService ?? OffsendIgnoreService(configuration: configuration)
        self.syncService = syncService ?? OffsendIgnoreSyncService(configuration: configuration)
        self.configLoader = configLoader
    }

    public func run(
        directoryURL: URL,
        dryRun: Bool = false,
        includeRecommended: Bool = false
    ) -> ProtectReport {
        let root = directoryURL.standardizedFileURL
        var errors: [String] = []
        // `ignore.tools` narrows which AI tools get managed files; absent = all.
        let configuration = self.configuration.filtered(
            tools: (try? configLoader.load(from: root))?.ignore?.toolIDs
        )

        // Protect syncs the managed block itself below, so prepare skips it.
        let prepare = prepareService.run(
            directoryURL: root,
            dryRun: dryRun,
            syncPatterns: false,
            materializeManagedIgnore: false
        )
        errors.append(contentsOf: prepare.errors)

        let audit = auditor.audit(directoryURL: root, configuration: configuration)
        if audit.isDirectoryUnavailable {
            errors.append(contentsOf: audit.errors.map(\.message))
            return ProtectReport(
                directoryPath: root.path,
                dryRun: dryRun,
                includeRecommended: includeRecommended,
                patterns: [],
                prepare: prepare,
                ignore: nil,
                sync: nil,
                remainingRequiredCount: 0,
                remainingRecommendedCount: 0,
                scanIncomplete: false,
                errors: errors
            )
        }

        let patterns = Self.patternsToIgnore(
            from: audit,
            includeRecommended: includeRecommended
        )

        var ignoreReport: IgnoreReport?
        var syncReport: IgnoreSyncReport?
        var addedToConfig: [String] = []

        let hasProjectConfig = configLoader.configURL(for: root) != nil

        if !patterns.isEmpty {
            if hasProjectConfig {
                let promoted = syncService.promotePatterns(patterns, directoryURL: root, dryRun: dryRun)
                addedToConfig = promoted.added
                syncReport = promoted.sync
                errors.append(contentsOf: promoted.sync.errors)
            } else {
                // Fallback when no .offsend.yml yet: write ignore files directly.
                ignoreReport = ignoreService.run(
                    directoryURL: root,
                    patterns: patterns,
                    dryRun: dryRun
                )
                errors.append(contentsOf: ignoreReport?.errors ?? [])
            }
        } else if hasProjectConfig {
            syncReport = syncService.run(directoryURL: root, dryRun: dryRun)
            errors.append(contentsOf: syncReport?.errors ?? [])
        }

        let after: AIWorkspacePrivacyAuditResult
        if dryRun {
            after = audit
        } else {
            after = auditor.audit(directoryURL: root, configuration: configuration)
        }

        let remaining = Self.exposureCounts(from: after)
        return ProtectReport(
            directoryPath: root.path,
            dryRun: dryRun,
            includeRecommended: includeRecommended,
            patterns: patterns,
            prepare: prepare,
            ignore: ignoreReport,
            sync: syncReport,
            addedToConfig: addedToConfig,
            remainingRequiredCount: remaining.required,
            remainingRecommendedCount: remaining.recommended,
            scanIncomplete: !after.exposureScanCompletion.isComplete,
            errors: Array(Set(errors)).sorted()
        )
    }

    static func patternsToIgnore(
        from audit: AIWorkspacePrivacyAuditResult,
        includeRecommended: Bool
    ) -> [String] {
        var seen = Set<String>()
        var patterns: [String] = []
        for finding in audit.missingSensitivePatterns {
            let severity = finding.pattern.severity
            let include = severity == .required
                || (includeRecommended && severity == .recommended)
            guard include else { continue }
            let line = finding.pattern.canonicalIgnoreLine
            guard !line.isEmpty, seen.insert(line).inserted else { continue }
            patterns.append(line)
        }
        return patterns.sorted()
    }

    private static func exposureCounts(
        from audit: AIWorkspacePrivacyAuditResult
    ) -> (required: Int, recommended: Int) {
        var required = Set<String>()
        var recommended = Set<String>()
        for finding in audit.sensitivePatternFindings {
            switch finding.pattern.severity {
            case .required:
                required.formUnion(finding.exposedRelativePaths)
            case .recommended:
                recommended.formUnion(finding.exposedRelativePaths)
            case .informational:
                break
            }
        }
        return (required.count, recommended.count)
    }
}
