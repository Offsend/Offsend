import Foundation

/// Upserts paths into `.git/info/exclude` inside an offsend managed block.
/// Each caller writes its own named section so independent writers (ignore-file
/// sync vs hook install) never overwrite each other's entries.
public struct OffsendLocalGitExcludeService: Sendable {
    /// Section name shared with `.gitignore` managed blocks. Formerly written to
    /// `.git/info/exclude` when `ignore.commit` was false; sync now uses
    /// `.gitignore` and removes any leftover exclude section on migrate.
    public static let ignoreFilesSection = "ignore-files"
    /// Section holding AI editor hook paths kept local by `hooks.publish: false`.
    public static let hooksSection = "hooks"

    private let fileManager: FileManager
    private let gitResolver: GitRepositoryResolver

    public init(
        fileManager: FileManager = .default,
        gitResolver: GitRepositoryResolver = GitRepositoryResolver()
    ) {
        self.fileManager = fileManager
        self.gitResolver = gitResolver
    }

    public struct Report: Sendable, Equatable {
        public let excludePath: String?
        public let updated: Bool
        /// True when the directory is not inside a git repository, so there is no
        /// `.git/info/exclude` to manage.
        public let skippedNotARepository: Bool
        public let errors: [String]

        public init(
            excludePath: String?,
            updated: Bool,
            skippedNotARepository: Bool = false,
            errors: [String] = []
        ) {
            self.excludePath = excludePath
            self.updated = updated
            self.skippedNotARepository = skippedNotARepository
            self.errors = errors
        }

        public var hasErrors: Bool { !errors.isEmpty }
    }

    /// With `merge`, patterns already in the section are kept (incremental writers
    /// like `hook install` per target); without it the section is replaced.
    public func upsertPatterns(
        _ patterns: [String],
        repositoryURL: URL,
        section: String,
        merge: Bool = false,
        dryRun: Bool = false
    ) -> Report {
        guard let root = try? gitResolver.repositoryRoot(startingAt: repositoryURL.standardizedFileURL) else {
            return Report(excludePath: nil, updated: false, skippedNotARepository: true)
        }
        let excludeURL = gitResolver.infoExcludeURL(in: root)
        let existing = try? String(contentsOf: excludeURL, encoding: .utf8)
        var effective = patterns
        if merge,
           let existing,
           let current = OffsendManagedIgnoreBlock.patterns(in: existing, section: section) {
            effective = current + patterns
        }
        let upsert = OffsendManagedIgnoreBlock.upsert(patterns: effective, into: existing, section: section)

        switch upsert.result {
        case .malformed(let message):
            return Report(excludePath: excludeURL.path, updated: false, errors: [message])
        case .unchanged:
            return Report(excludePath: excludeURL.path, updated: false)
        case .created, .updated:
            if dryRun {
                return Report(excludePath: excludeURL.path, updated: true)
            }
            return write(upsert.contents, to: excludeURL)
        }
    }

    /// Removes the managed section entirely (e.g. when `ignore.commit` flips to true).
    public func removeSection(
        _ section: String,
        repositoryURL: URL,
        dryRun: Bool = false
    ) -> Report {
        guard let root = try? gitResolver.repositoryRoot(startingAt: repositoryURL.standardizedFileURL) else {
            return Report(excludePath: nil, updated: false, skippedNotARepository: true)
        }
        let excludeURL = gitResolver.infoExcludeURL(in: root)
        guard let existing = try? String(contentsOf: excludeURL, encoding: .utf8),
              let cleaned = OffsendManagedIgnoreBlock.removing(section: section, from: existing) else {
            return Report(excludePath: excludeURL.path, updated: false)
        }
        if dryRun {
            return Report(excludePath: excludeURL.path, updated: true)
        }
        return write(cleaned, to: excludeURL)
    }

    /// True when the exclude file contains a managed section (used by doctor checks).
    public func hasSection(_ section: String, repositoryURL: URL) -> Bool {
        guard let root = try? gitResolver.repositoryRoot(startingAt: repositoryURL.standardizedFileURL) else {
            return false
        }
        let excludeURL = gitResolver.infoExcludeURL(in: root)
        guard let existing = try? String(contentsOf: excludeURL, encoding: .utf8) else { return false }
        return OffsendManagedIgnoreBlock.patterns(in: existing, section: section) != nil
    }

    private func write(_ contents: String, to excludeURL: URL) -> Report {
        do {
            try fileManager.createDirectory(
                at: excludeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: excludeURL, atomically: true, encoding: .utf8)
            return Report(excludePath: excludeURL.path, updated: true)
        } catch {
            return Report(
                excludePath: excludeURL.path,
                updated: false,
                errors: ["Failed to update \(excludeURL.path): \(error.localizedDescription)"]
            )
        }
    }

    /// Hook paths written by `hook install` for the given editor configs that should
    /// stay local when `hooks.publish` is false.
    public static func aiHookExcludePatterns(configRelativePaths: [String]) -> [String] {
        var patterns = configRelativePaths
        patterns.append(".offsend/hooks/")
        return patterns
    }

    /// Every hook path Offsend can write, for doctor-style audits.
    public static let allKnownHookRelativePaths: [String] = [
        ".cursor/hooks.json",
        ".claude/settings.json",
        ".windsurf/hooks.json",
        ".codex/hooks.json",
        ".offsend/hooks/",
    ]
}
