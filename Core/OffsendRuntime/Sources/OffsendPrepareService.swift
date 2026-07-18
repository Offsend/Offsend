import Foundation
import WorkspacePolicyCore

/// One AI ignore/rule file that `OffsendPrepareService` can create.
public struct PreparePlannedFile: Sendable, Equatable {
    public let relativePath: String
    public let toolName: String
    public let required: Bool

    public init(relativePath: String, toolName: String, required: Bool) {
        self.relativePath = relativePath
        self.toolName = toolName
        self.required = required
    }
}

/// An existing ignore file that would receive extra sensitive-data pattern lines.
public struct PreparePlannedPatternUpdate: Sendable, Equatable {
    public let relativePath: String
    public let addedLines: [String]

    public init(relativePath: String, addedLines: [String]) {
        self.relativePath = relativePath
        self.addedLines = addedLines
    }
}

public struct PrepareReport: Sendable, Equatable {
    public let directoryPath: String
    public let dryRun: Bool
    /// Missing files that `prepare` created (or would create in dry-run mode).
    public let plannedCreates: [PreparePlannedFile]
    /// Existing ignore files that would gain sensitive-pattern lines (dry-run only).
    public let plannedUpdates: [PreparePlannedPatternUpdate]
    /// Files actually written. Empty in dry-run mode.
    public let createdRelativePaths: [String]
    /// Existing files actually updated with new pattern lines. Empty in dry-run mode.
    public let updatedRelativePaths: [String]
    public let errors: [String]

    public init(
        directoryPath: String,
        dryRun: Bool,
        plannedCreates: [PreparePlannedFile],
        plannedUpdates: [PreparePlannedPatternUpdate],
        createdRelativePaths: [String],
        updatedRelativePaths: [String],
        errors: [String]
    ) {
        self.directoryPath = directoryPath
        self.dryRun = dryRun
        self.plannedCreates = plannedCreates
        self.plannedUpdates = plannedUpdates
        self.createdRelativePaths = createdRelativePaths
        self.updatedRelativePaths = updatedRelativePaths
        self.errors = errors
    }

    public var hasErrors: Bool { !errors.isEmpty }
}

/// Creates missing AI ignore/rule files (`.cursorignore`, `.claudeignore`, …) for a
/// project, mirroring the macOS app's one-click directory fix. Missing files are always
/// created; with `syncPatterns`, missing sensitive-data patterns are also appended to
/// ignore files that already exist.
public struct OffsendPrepareService: Sendable {
    private let configuration: AIWorkspacePrivacyAuditConfiguration
    private let auditor: AIWorkspacePrivacyAuditor
    private let fixer: AIWorkspacePrivacyFixer
    private let fileManager: FileManager

    public init(
        context: OffsendRuntimeContext,
        auditor: AIWorkspacePrivacyAuditor = AIWorkspacePrivacyAuditor(),
        fixer: AIWorkspacePrivacyFixer = AIWorkspacePrivacyFixer(),
        fileManager: FileManager = .default
    ) {
        self.init(
            configuration: OffsendConfiguration.directoryCheckConfiguration(context: context),
            auditor: auditor,
            fixer: fixer,
            fileManager: fileManager
        )
    }

    public init(
        configuration: AIWorkspacePrivacyAuditConfiguration,
        auditor: AIWorkspacePrivacyAuditor = AIWorkspacePrivacyAuditor(),
        fixer: AIWorkspacePrivacyFixer = AIWorkspacePrivacyFixer(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.auditor = auditor
        self.fixer = fixer
        self.fileManager = fileManager
    }

    public func run(
        directoryURL: URL,
        dryRun: Bool = false,
        syncPatterns: Bool = false,
        materializeManagedIgnore: Bool = true
    ) -> PrepareReport {
        let standardizedURL = directoryURL.standardizedFileURL
        let projectConfig = try? ProjectConfigLoader().load(from: standardizedURL)
        // `ignore.tools` narrows which AI tools get managed files; absent = all.
        let configuration = self.configuration.filtered(tools: projectConfig?.ignore?.toolIDs)
        let audit = auditor.audit(directoryURL: standardizedURL, configuration: configuration)

        if audit.isDirectoryUnavailable {
            return report(
                directoryPath: standardizedURL.path,
                dryRun: dryRun,
                errors: audit.errors.map(\.message)
            )
        }

        // Missing, fixable, non-informational ignore/rule files. Informational
        // suggestions (.gitignore, AGENTS.md) are not auto-created.
        let missingFindings = audit.ruleFindings.filter {
            !$0.isSatisfied && $0.rule.severity != .informational && $0.rule.fix != nil
        }

        let plannedCreates = missingFindings
            .compactMap { finding -> PreparePlannedFile? in
                guard let fix = finding.rule.fix else { return nil }
                return PreparePlannedFile(
                    relativePath: fix.relativePath,
                    toolName: finding.rule.toolName,
                    required: finding.rule.severity == .required
                )
            }
            .sorted { $0.relativePath < $1.relativePath }

        // Build the fix selection. Missing rule files are always selected so they get
        // created. When syncing patterns, also select existing scanning ignore files so
        // their missing pattern lines are appended.
        var ruleIDs = Set(missingFindings.map(\.rule.id))

        // Managed rule files (offsend_privacy.*) that exist but drifted from the
        // template are selected too, so the fixer restores their contents.
        let driftedManagedRules = Self.driftedManagedRules(
            configuration: configuration,
            rootURL: standardizedURL,
            fileManager: fileManager
        )
        ruleIDs.formUnion(driftedManagedRules.map(\.id))
        var patternIDs: Set<String> = []
        let missingPatterns = syncPatterns ? audit.missingSensitivePatterns : []
        if !missingPatterns.isEmpty {
            patternIDs = Set(missingPatterns.map(\.pattern.id))
            let existingScanRuleIDs = audit.ruleFindings
                .filter { $0.isSatisfied && $0.rule.scansForSensitivePatterns }
                .map(\.rule.id)
            ruleIDs.formUnion(existingScanRuleIDs)
        }

        let selection = AIWorkspacePrivacyFixSelection(ruleIDs: ruleIDs, patternIDs: patternIDs)

        if dryRun {
            return report(
                directoryPath: standardizedURL.path,
                dryRun: true,
                plannedCreates: plannedCreates,
                plannedUpdates: plannedPatternUpdates(
                    missingPatterns: missingPatterns,
                    selection: selection,
                    audit: audit,
                    configuration: configuration,
                    rootURL: standardizedURL
                )
            )
        }

        guard !selection.ruleIDs.isEmpty || !selection.patternIDs.isEmpty else {
            return report(directoryPath: standardizedURL.path, dryRun: false)
        }

        let fixResult = fixer.fix(result: audit, configuration: configuration, selection: selection)
        var errors = fixResult.errors.map(\.message)
        var created = fixResult.createdRelativePaths
        var updated = fixResult.updatedRelativePaths

        // When project config defines ignore.patterns, materialize the managed block.
        // Callers that sync themselves right after (protect) opt out.
        if materializeManagedIgnore,
           let config = projectConfig,
           config.ignore != nil {
            let sync = OffsendIgnoreSyncService(configuration: configuration).run(
                directoryURL: standardizedURL,
                dryRun: false
            )
            errors.append(contentsOf: sync.errors)
            created = Array(Set(created + sync.createdRelativePaths)).sorted()
            updated = Array(Set(updated + sync.updatedRelativePaths)).sorted()
        }

        return report(
            directoryPath: standardizedURL.path,
            dryRun: false,
            createdRelativePaths: created,
            updatedRelativePaths: updated,
            errors: errors
        )
    }

    /// Managed-content rules (offsend_privacy.*) whose file on disk exists but
    /// differs from the template (user edits are restored, not merged).
    public static func driftedManagedRules(
        configuration: AIWorkspacePrivacyAuditConfiguration,
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> [(id: String, relativePath: String)] {
        var drifted: [(id: String, relativePath: String)] = []
        for rule in configuration.rules {
            guard let fix = rule.fix, fix.strategy == .keepManagedContent else { continue }
            let url = rootURL.appendingPathComponent(fix.relativePath)
            guard fileManager.fileExists(atPath: url.path),
                  let existing = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            if normalizedFileContents(existing) != normalizedFileContents(fix.contents) {
                drifted.append((id: rule.id, relativePath: fix.relativePath))
            }
        }
        return drifted.sorted { $0.relativePath < $1.relativePath }
    }

    private static func normalizedFileContents(_ contents: String) -> String {
        contents.hasSuffix("\n") ? contents : contents + "\n"
    }

    /// Existing ignore files that would receive new pattern lines, with the exact lines
    /// that are missing from each file on disk (so dry-run output is accurate).
    private func plannedPatternUpdates(
        missingPatterns: [AIWorkspaceSensitivePatternFinding],
        selection: AIWorkspacePrivacyFixSelection,
        audit: AIWorkspacePrivacyAuditResult,
        configuration: AIWorkspacePrivacyAuditConfiguration,
        rootURL: URL
    ) -> [PreparePlannedPatternUpdate] {
        guard !missingPatterns.isEmpty else { return [] }

        let lines = missingPatterns.map(\.pattern.canonicalIgnoreLine)
        let targets = AIWorkspacePrivacyFixPlanner.patternTargetRelativePaths(
            for: audit,
            configuration: configuration,
            selection: selection
        )

        return targets.compactMap { relativePath -> PreparePlannedPatternUpdate? in
            let url = rootURL.appendingPathComponent(relativePath)
            // Files that do not exist yet are created from the full template, which already
            // covers every default pattern, so they are reported as creates, not updates.
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let existing = Self.ignorePatterns(in: contents)
            let missingLines = lines.filter { !existing.contains($0) }
            guard !missingLines.isEmpty else { return nil }
            return PreparePlannedPatternUpdate(
                relativePath: relativePath,
                addedLines: Array(Set(missingLines)).sorted()
            )
        }
        .sorted { $0.relativePath < $1.relativePath }
    }

    /// Mirrors the ignore-file pattern normalization used when writing files: trim
    /// whitespace, drop blank lines and `#` comments.
    private static func ignorePatterns(in contents: String) -> Set<String> {
        Set(
            contents
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        )
    }

    private func report(
        directoryPath: String,
        dryRun: Bool,
        plannedCreates: [PreparePlannedFile] = [],
        plannedUpdates: [PreparePlannedPatternUpdate] = [],
        createdRelativePaths: [String] = [],
        updatedRelativePaths: [String] = [],
        errors: [String] = []
    ) -> PrepareReport {
        PrepareReport(
            directoryPath: directoryPath,
            dryRun: dryRun,
            plannedCreates: plannedCreates,
            plannedUpdates: plannedUpdates,
            createdRelativePaths: createdRelativePaths.sorted(),
            updatedRelativePaths: updatedRelativePaths.sorted(),
            errors: errors
        )
    }
}
