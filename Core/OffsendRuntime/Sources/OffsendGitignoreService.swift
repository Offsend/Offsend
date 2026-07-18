import Foundation

/// Upserts paths into root `.gitignore` inside an offsend managed block.
/// Used when `ignore.commit` is false so AI ignore files stay untracked for the
/// whole team (unlike local-only `.git/info/exclude`).
public struct OffsendGitignoreService: Sendable {
    public static let relativePath = ".gitignore"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public struct Report: Sendable, Equatable {
        public let gitignorePath: String
        public let updated: Bool
        public let errors: [String]

        public init(
            gitignorePath: String,
            updated: Bool,
            errors: [String] = []
        ) {
            self.gitignorePath = gitignorePath
            self.updated = updated
            self.errors = errors
        }

        public var hasErrors: Bool { !errors.isEmpty }
    }

    public func upsertPatterns(
        _ patterns: [String],
        directoryURL: URL,
        section: String,
        dryRun: Bool = false
    ) -> Report {
        let url = directoryURL.standardizedFileURL.appendingPathComponent(Self.relativePath)
        let existing = fileManager.fileExists(atPath: url.path)
            ? (try? String(contentsOf: url, encoding: .utf8))
            : nil
        let upsert = OffsendManagedIgnoreBlock.upsert(
            patterns: patterns,
            into: existing,
            section: section
        )

        switch upsert.result {
        case .malformed(let message):
            return Report(gitignorePath: url.path, updated: false, errors: [message])
        case .unchanged:
            return Report(gitignorePath: url.path, updated: false)
        case .created, .updated:
            if dryRun {
                return Report(gitignorePath: url.path, updated: true)
            }
            return write(upsert.contents, to: url)
        }
    }

    /// Removes the managed section (e.g. when `ignore.commit` flips to true).
    public func removeSection(
        _ section: String,
        directoryURL: URL,
        dryRun: Bool = false
    ) -> Report {
        let url = directoryURL.standardizedFileURL.appendingPathComponent(Self.relativePath)
        guard fileManager.fileExists(atPath: url.path),
              let existing = try? String(contentsOf: url, encoding: .utf8),
              let cleaned = OffsendManagedIgnoreBlock.removing(section: section, from: existing) else {
            return Report(gitignorePath: url.path, updated: false)
        }
        if dryRun {
            return Report(gitignorePath: url.path, updated: true)
        }
        return write(cleaned, to: url)
    }

    public func hasSection(_ section: String, directoryURL: URL) -> Bool {
        let url = directoryURL.standardizedFileURL.appendingPathComponent(Self.relativePath)
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return OffsendManagedIgnoreBlock.patterns(in: existing, section: section) != nil
    }

    private func write(_ contents: String, to url: URL) -> Report {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return Report(gitignorePath: url.path, updated: true)
        } catch {
            return Report(
                gitignorePath: url.path,
                updated: false,
                errors: ["Failed to update \(url.path): \(error.localizedDescription)"]
            )
        }
    }
}
