import Foundation
import WorkspacePolicyCore

/// An existing ignore file that would receive new pattern lines (dry-run only).
public struct IgnorePlannedUpdate: Sendable, Equatable {
    public let relativePath: String
    public let addedLines: [String]

    public init(relativePath: String, addedLines: [String]) {
        self.relativePath = relativePath
        self.addedLines = addedLines
    }
}

public struct IgnoreReport: Sendable, Equatable {
    public let directoryPath: String
    public let dryRun: Bool
    /// Normalized pattern lines the command applies.
    public let patterns: [String]
    /// Files that would be created (dry-run only).
    public let plannedCreates: [String]
    /// Existing files that would gain lines (dry-run only).
    public let plannedUpdates: [IgnorePlannedUpdate]
    public let createdRelativePaths: [String]
    public let updatedRelativePaths: [String]
    /// Files that already contained every pattern.
    public let unchangedRelativePaths: [String]
    public let errors: [String]

    public init(
        directoryPath: String,
        dryRun: Bool,
        patterns: [String],
        plannedCreates: [String],
        plannedUpdates: [IgnorePlannedUpdate],
        createdRelativePaths: [String],
        updatedRelativePaths: [String],
        unchangedRelativePaths: [String],
        errors: [String]
    ) {
        self.directoryPath = directoryPath
        self.dryRun = dryRun
        self.patterns = patterns
        self.plannedCreates = plannedCreates
        self.plannedUpdates = plannedUpdates
        self.createdRelativePaths = createdRelativePaths
        self.updatedRelativePaths = updatedRelativePaths
        self.unchangedRelativePaths = unchangedRelativePaths
        self.errors = errors
    }

    public var hasErrors: Bool { !errors.isEmpty }
}

/// Adds paths or glob patterns to every AI ignore file in a project
/// (`.cursorignore`, `.claudeignore`, `.aiexclude`, …). Only existing ignore
/// files are updated; when the project has none yet, the standard set is
/// created first (same files as `OffsendPrepareService`). Does not write AI
/// patterns into `.gitignore` (that file only lists AI ignore paths when
/// `ignore.commit` is false, via `offsend sync`).
public struct OffsendIgnoreService: Sendable {
    private let configuration: AIWorkspacePrivacyAuditConfiguration
    private let fixer: AIWorkspacePrivacyFixer
    private let fileManager: FileManager

    public init(
        context: OffsendRuntimeContext,
        fixer: AIWorkspacePrivacyFixer = AIWorkspacePrivacyFixer(),
        fileManager: FileManager = .default
    ) {
        self.init(
            configuration: OffsendConfiguration.directoryCheckConfiguration(context: context),
            fixer: fixer,
            fileManager: fileManager
        )
    }

    public init(
        configuration: AIWorkspacePrivacyAuditConfiguration,
        fixer: AIWorkspacePrivacyFixer = AIWorkspacePrivacyFixer(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fixer = fixer
        self.fileManager = fileManager
    }

    public func run(
        directoryURL: URL,
        patterns rawPatterns: [String],
        dryRun: Bool = false
    ) -> IgnoreReport {
        let root = directoryURL.standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return report(
                directoryPath: root.path,
                dryRun: dryRun,
                patterns: [],
                errors: ["Directory does not exist: \(root.path)"]
            )
        }

        var errors: [String] = []
        var patterns: [String] = []
        var seen = Set<String>()
        for raw in rawPatterns {
            switch Self.normalizePattern(raw, rootURL: root, fileManager: fileManager) {
            case .pattern(let line):
                if seen.insert(line).inserted { patterns.append(line) }
            case .blank:
                continue
            case .outsideRoot(let path):
                errors.append("Path is outside the target directory: \(path)")
            }
        }
        guard !patterns.isEmpty else {
            if errors.isEmpty { errors.append("No patterns to add.") }
            return report(directoryPath: root.path, dryRun: dryRun, patterns: [], errors: errors)
        }

        // Target every gitignore-style AI ignore file the audit knows about.
        // Rule files (.cursor/rules) and informational suggestions (.gitignore,
        // AGENTS.md) are never touched.
        let ignoreFilePaths = configuration.rules
            .filter(\.scansForSensitivePatterns)
            .compactMap(\.fix?.relativePath)
        let existing = ignoreFilePaths.filter {
            fileManager.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        let creatingStandardSet = existing.isEmpty
        let targets = creatingStandardSet ? ignoreFilePaths : existing

        if dryRun {
            var plannedCreates: [String] = []
            var plannedUpdates: [IgnorePlannedUpdate] = []
            for relativePath in targets {
                let url = root.appendingPathComponent(relativePath)
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    plannedCreates.append(relativePath)
                    continue
                }
                let present = Self.ignorePatterns(in: contents)
                let missing = patterns.filter { !present.contains($0) }
                if !missing.isEmpty {
                    plannedUpdates.append(
                        IgnorePlannedUpdate(relativePath: relativePath, addedLines: missing)
                    )
                }
            }
            return report(
                directoryPath: root.path,
                dryRun: true,
                patterns: patterns,
                plannedCreates: plannedCreates.sorted(),
                plannedUpdates: plannedUpdates.sorted { $0.relativePath < $1.relativePath },
                errors: errors
            )
        }

        var created: [String] = []
        var updated: [String] = []
        var unchanged: [String] = []
        for relativePath in targets {
            let outcome = fixer.appendIgnoreLines(
                patterns,
                toRelativePath: relativePath,
                in: root,
                templateContentsIfMissing: creatingStandardSet
                    ? AIWorkspacePrivacyIgnoreTemplate.contents
                    : nil
            )
            switch outcome {
            case .created(let path):
                created.append(path)
            case .updated(let path):
                updated.append(path)
            case .unchanged(let path):
                unchanged.append(path)
            case .failed(let error):
                errors.append(error.message)
            }
        }

        return report(
            directoryPath: root.path,
            dryRun: false,
            patterns: patterns,
            createdRelativePaths: created.sorted(),
            updatedRelativePaths: updated.sorted(),
            unchangedRelativePaths: unchanged.sorted(),
            errors: errors
        )
    }

    enum NormalizedPattern: Equatable {
        case pattern(String)
        case blank
        case outsideRoot(String)
    }

    /// Trims the input, strips a leading `./`, re-roots absolute paths that live
    /// under the root, and appends `/` when the pattern names an existing directory.
    /// Glob patterns pass through untouched.
    static func normalizePattern(
        _ raw: String,
        rootURL: URL,
        fileManager: FileManager
    ) -> NormalizedPattern {
        var pattern = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty, !pattern.hasPrefix("#") else { return .blank }

        if pattern.hasPrefix("/") {
            let rootPrefix = rootURL.path + "/"
            guard pattern.hasPrefix(rootPrefix), pattern.count > rootPrefix.count else {
                return .outsideRoot(pattern)
            }
            pattern = String(pattern.dropFirst(rootPrefix.count))
        }
        while pattern.hasPrefix("./") {
            pattern = String(pattern.dropFirst(2))
        }
        guard !pattern.isEmpty else { return .blank }

        var isDirectory: ObjCBool = false
        if !pattern.hasSuffix("/"),
           fileManager.fileExists(
               atPath: rootURL.appendingPathComponent(pattern).path,
               isDirectory: &isDirectory
           ),
           isDirectory.boolValue {
            pattern += "/"
        }
        return .pattern(pattern)
    }

    /// Mirrors ignore-file normalization: trim, drop blanks and `#` comments.
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
        patterns: [String],
        plannedCreates: [String] = [],
        plannedUpdates: [IgnorePlannedUpdate] = [],
        createdRelativePaths: [String] = [],
        updatedRelativePaths: [String] = [],
        unchangedRelativePaths: [String] = [],
        errors: [String] = []
    ) -> IgnoreReport {
        IgnoreReport(
            directoryPath: directoryPath,
            dryRun: dryRun,
            patterns: patterns,
            plannedCreates: plannedCreates,
            plannedUpdates: plannedUpdates,
            createdRelativePaths: createdRelativePaths,
            updatedRelativePaths: updatedRelativePaths,
            unchangedRelativePaths: unchangedRelativePaths,
            errors: errors
        )
    }
}
