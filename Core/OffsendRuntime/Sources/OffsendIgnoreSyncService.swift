import Foundation
import WorkspacePolicyCore
import Yams

public struct IgnoreSyncReport: Sendable, Equatable {
    public let directoryPath: String
    public let dryRun: Bool
    public let patterns: [String]
    public let commitIgnoreFiles: Bool
    public let createdRelativePaths: [String]
    public let updatedRelativePaths: [String]
    public let unchangedRelativePaths: [String]
    public let excludeUpdated: Bool
    public let excludePath: String?
    public let errors: [String]

    public init(
        directoryPath: String,
        dryRun: Bool,
        patterns: [String],
        commitIgnoreFiles: Bool,
        createdRelativePaths: [String] = [],
        updatedRelativePaths: [String] = [],
        unchangedRelativePaths: [String] = [],
        excludeUpdated: Bool = false,
        excludePath: String? = nil,
        errors: [String] = []
    ) {
        self.directoryPath = directoryPath
        self.dryRun = dryRun
        self.patterns = patterns
        self.commitIgnoreFiles = commitIgnoreFiles
        self.createdRelativePaths = createdRelativePaths
        self.updatedRelativePaths = updatedRelativePaths
        self.unchangedRelativePaths = unchangedRelativePaths
        self.excludeUpdated = excludeUpdated
        self.excludePath = excludePath
        self.errors = errors
    }

    public var hasErrors: Bool { !errors.isEmpty }
}

/// Materializes `ignore.patterns` from `.offsend.yml` into AI ignore files (managed
/// block) and, when `ignore.commit` is false, keeps those paths out of git via
/// `.git/info/exclude`.
public struct OffsendIgnoreSyncService: Sendable {
    private let configuration: AIWorkspacePrivacyAuditConfiguration
    private let fileManager: FileManager
    private let gitResolver: GitRepositoryResolver
    private let configLoader: ProjectConfigLoader
    private let excludeService: OffsendLocalGitExcludeService

    public init(
        context: OffsendRuntimeContext,
        fileManager: FileManager = .default,
        gitResolver: GitRepositoryResolver = GitRepositoryResolver(),
        configLoader: ProjectConfigLoader = ProjectConfigLoader()
    ) {
        self.init(
            configuration: OffsendConfiguration.directoryCheckConfiguration(context: context),
            fileManager: fileManager,
            gitResolver: gitResolver,
            configLoader: configLoader
        )
    }

    public init(
        configuration: AIWorkspacePrivacyAuditConfiguration = .default,
        fileManager: FileManager = .default,
        gitResolver: GitRepositoryResolver = GitRepositoryResolver(),
        configLoader: ProjectConfigLoader = ProjectConfigLoader()
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.gitResolver = gitResolver
        self.configLoader = configLoader
        self.excludeService = OffsendLocalGitExcludeService(
            fileManager: fileManager,
            gitResolver: gitResolver
        )
    }

    /// Relative paths of gitignore-style AI ignore files Offsend manages.
    public static func managedIgnoreRelativePaths(
        configuration: AIWorkspacePrivacyAuditConfiguration = .default
    ) -> [String] {
        configuration.rules
            .filter(\.scansForSensitivePatterns)
            .compactMap(\.fix?.relativePath)
            .sorted()
    }

    public func run(directoryURL: URL, dryRun: Bool = false) -> IgnoreSyncReport {
        // Materialize at the repository root so running from a subdirectory does
        // not scatter ignore files: the config lives at the root and patterns are
        // root-relative.
        let root = materializationRoot(for: directoryURL)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return IgnoreSyncReport(
                directoryPath: root.path,
                dryRun: dryRun,
                patterns: [],
                commitIgnoreFiles: false,
                errors: ["Directory does not exist: \(root.path)"]
            )
        }

        let config: OffsendProjectConfig?
        do {
            config = try configLoader.load(from: root)
        } catch {
            return IgnoreSyncReport(
                directoryPath: root.path,
                dryRun: dryRun,
                patterns: [],
                commitIgnoreFiles: false,
                errors: ["Failed to load \(ProjectConfigLoader.filename): \(error.localizedDescription)"]
            )
        }

        guard let config else {
            return IgnoreSyncReport(
                directoryPath: root.path,
                dryRun: dryRun,
                patterns: [],
                commitIgnoreFiles: false,
                errors: ["No \(ProjectConfigLoader.filename) in \(root.path). Run `offsend init` first."]
            )
        }

        return run(
            directoryURL: root,
            patterns: config.ignore?.patterns ?? [],
            commitIgnoreFiles: config.ignore?.commitsIgnoreFiles ?? false,
            dryRun: dryRun
        )
    }

    public func run(
        directoryURL: URL,
        patterns rawPatterns: [String],
        commitIgnoreFiles: Bool,
        dryRun: Bool = false
    ) -> IgnoreSyncReport {
        let root = directoryURL.standardizedFileURL
        var errors: [String] = []
        let patterns = OffsendManagedIgnoreBlock.normalizePatterns(rawPatterns)
        let targets = Self.managedIgnoreRelativePaths(configuration: configuration)

        var created: [String] = []
        var updated: [String] = []
        var unchanged: [String] = []

        for relativePath in targets {
            let url = root.appendingPathComponent(relativePath)
            let fileExists = fileManager.fileExists(atPath: url.path)
            let existing = fileExists ? (try? String(contentsOf: url, encoding: .utf8)) : nil
            let seed = existing ?? AIWorkspacePrivacyIgnoreTemplate.contents
            let upsert = OffsendManagedIgnoreBlock.upsert(patterns: patterns, into: seed)

            switch upsert.result {
            case .malformed(let message):
                errors.append("\(relativePath): \(message)")
                continue
            case .created, .updated, .unchanged:
                break
            }

            let needsWrite = !fileExists || upsert.result != .unchanged
            if !needsWrite {
                unchanged.append(relativePath)
                continue
            }

            if dryRun {
                if fileExists {
                    updated.append(relativePath)
                } else {
                    created.append(relativePath)
                }
                continue
            }

            do {
                try writeFile(upsert.contents, to: url)
                if fileExists {
                    updated.append(relativePath)
                } else {
                    created.append(relativePath)
                }
            } catch {
                let verb = fileExists ? "update" : "create"
                errors.append("Failed to \(verb) \(relativePath): \(error.localizedDescription)")
            }
        }

        let exclude: OffsendLocalGitExcludeService.Report
        if commitIgnoreFiles {
            // commit: true means the files may be tracked; drop any stale local
            // exclusion left over from a previous commit: false configuration.
            exclude = excludeService.removeSection(
                OffsendLocalGitExcludeService.ignoreFilesSection,
                repositoryURL: root,
                dryRun: dryRun
            )
        } else {
            exclude = excludeService.upsertPatterns(
                targets,
                repositoryURL: root,
                section: OffsendLocalGitExcludeService.ignoreFilesSection,
                dryRun: dryRun
            )
        }
        errors.append(contentsOf: exclude.errors)

        return IgnoreSyncReport(
            directoryPath: root.path,
            dryRun: dryRun,
            patterns: patterns,
            commitIgnoreFiles: commitIgnoreFiles,
            createdRelativePaths: created.sorted(),
            updatedRelativePaths: updated.sorted(),
            unchangedRelativePaths: unchanged.sorted(),
            excludeUpdated: exclude.updated,
            excludePath: exclude.excludePath,
            errors: errors
        )
    }

    /// Promotes patterns into `.offsend.yml` then materializes them.
    public func promotePatterns(
        _ rawPatterns: [String],
        directoryURL: URL,
        dryRun: Bool = false
    ) -> (added: [String], configPath: String?, sync: IgnoreSyncReport) {
        let root = directoryURL.standardizedFileURL
        let repoRoot = materializationRoot(for: root)
        let configURL = repoRoot.appendingPathComponent(ProjectConfigLoader.filename)

        var normalized: [String] = []
        var errors: [String] = []
        var seen = Set<String>()
        for raw in rawPatterns {
            // Existing paths given relative to the working directory are re-anchored
            // to the repository root, where the config (and its patterns) live.
            let anchored = anchorToRoot(raw, workingDirectory: root, repositoryRoot: repoRoot)
            switch OffsendIgnoreService.normalizePattern(anchored, rootURL: repoRoot, fileManager: fileManager) {
            case .pattern(let line):
                if seen.insert(line).inserted { normalized.append(line) }
            case .blank:
                continue
            case .outsideRoot(let path):
                errors.append("Path is outside the target directory: \(path)")
            }
        }

        func failure(_ extraErrors: [String]) -> (added: [String], configPath: String?, sync: IgnoreSyncReport) {
            (
                [],
                fileManager.fileExists(atPath: configURL.path) ? configURL.path : nil,
                IgnoreSyncReport(
                    directoryPath: repoRoot.path,
                    dryRun: dryRun,
                    patterns: normalized,
                    commitIgnoreFiles: false,
                    errors: errors + extraErrors
                )
            )
        }

        guard errors.isEmpty else {
            return failure([])
        }
        guard !normalized.isEmpty else {
            return failure(["No patterns to add."])
        }
        guard fileManager.fileExists(atPath: configURL.path) else {
            return failure(["No \(ProjectConfigLoader.filename) at \(configURL.path). Run `offsend init` first."])
        }

        do {
            let existing = try String(contentsOf: configURL, encoding: .utf8)
            let merged = try ProjectConfigIgnoreMutator.mergingPatterns(intoYAML: existing, patterns: normalized)
            let decoded = try YAMLDecoder().decode(OffsendProjectConfig.self, from: merged.yaml)
            let commitIgnoreFiles = decoded.ignore?.commitsIgnoreFiles ?? false
            let mergedPatterns = OffsendManagedIgnoreBlock.normalizePatterns(decoded.ignore?.patterns ?? [])

            if !dryRun, merged.yaml != existing {
                try merged.yaml.write(to: configURL, atomically: true, encoding: .utf8)
            }

            let sync = run(
                directoryURL: repoRoot,
                patterns: mergedPatterns,
                commitIgnoreFiles: commitIgnoreFiles,
                dryRun: dryRun
            )
            return (merged.added, configURL.path, sync)
        } catch {
            errors.append("Failed to update \(configURL.path): \(error.localizedDescription)")
            return failure([])
        }
    }

    /// Repository root when inside a git repo, otherwise the directory itself.
    private func materializationRoot(for directoryURL: URL) -> URL {
        let standardized = directoryURL.standardizedFileURL
        return (try? gitResolver.repositoryRoot(startingAt: standardized)) ?? standardized
    }

    /// Re-anchors a working-directory-relative path to the repository root
    /// (`sub/` + `secrets/` → `sub/secrets/`). Globs and non-existing paths pass
    /// through unchanged.
    private func anchorToRoot(_ raw: String, workingDirectory: URL, repositoryRoot: URL) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard workingDirectory.path != repositoryRoot.path,
              !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("#"),
              fileManager.fileExists(atPath: workingDirectory.appendingPathComponent(trimmed).path) else {
            return raw
        }
        return workingDirectory.appendingPathComponent(trimmed).standardizedFileURL.path
    }

    private func writeFile(_ contents: String, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
