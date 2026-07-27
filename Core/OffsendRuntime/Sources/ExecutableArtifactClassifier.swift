import Foundation
import StorageCore

public enum ExecutableArtifactKind: String, Codable, Equatable, Sendable {
    case editorHookConfig
    case editorTaskConfig
    /// Editor settings that mix ordinary preferences with execution-sensitive keys.
    case editorSettings
    case gitDirectoryPointer
    case gitConfig
    case gitHook
    case shellStartupConfig
    case virtualEnvironmentInterpreter
    /// Files Python executes on interpreter startup (`*.pth`, `sitecustomize.py`).
    case pythonStartupHook
    case sshConfig
    case launchAgent
    /// Offsend's own project policy.
    case offsendPolicy
    /// Offsend's user-local trust snapshots and ledgers.
    case offsendTrustStore
}

public extension ExecutableArtifactKind {
    /// How the write-gate treats this surface. Enforcement follows from the kind
    /// alone, so keeping it here stops the classifier and the provenance summary
    /// from drifting apart. Listed exhaustively on purpose: a new kind should not
    /// silently inherit someone else's answer.
    var enforcement: ExecutableArtifactEnforcement {
        switch self {
        case .editorHookConfig, .editorTaskConfig,
             .gitDirectoryPointer, .gitConfig, .gitHook,
             .shellStartupConfig, .pythonStartupHook,
             .sshConfig, .launchAgent,
             .offsendPolicy, .offsendTrustStore:
            return .deny
        case .editorSettings:
            return .denyWhenContentExecutable
        case .virtualEnvironmentInterpreter:
            return .observe
        }
    }
}

public enum ExecutableArtifactEnforcement: String, Equatable, Sendable {
    case deny
    /// Deny only when the written content introduces an execution-sensitive key.
    case denyWhenContentExecutable
    case observe
}

public struct ExecutableArtifactMatch: Equatable, Sendable {
    public let path: String
    public let kind: ExecutableArtifactKind
    public let enforcement: ExecutableArtifactEnforcement

    public init(
        path: String,
        kind: ExecutableArtifactKind,
        enforcement: ExecutableArtifactEnforcement
    ) {
        self.path = path
        self.kind = kind
        self.enforcement = enforcement
    }
}

/// Classifies files whose contents can later be executed by an unsandboxed
/// editor, Git, interpreter discovery process, or launch daemon.
///
/// Rules match on path shape rather than exact repository-relative strings, so
/// nested repositories, subdirectory configs, and home-directory trust surfaces
/// are covered. Comparison is case- and Unicode-normalization-insensitive
/// because APFS resolves `.CURSOR/hooks.json` to the same file as
/// `.cursor/hooks.json`.
public struct ExecutableArtifactClassifier: Sendable {
    /// Directory + filename pairs for editor hook configuration, at any depth.
    private static let editorHookPairs: Set<[String]> = [
        [".cursor", "hooks.json"],
        [".claude", "settings.json"],
        [".claude", "settings.local.json"],
        [".windsurf", "hooks.json"],
        [".codex", "hooks.json"],
    ]

    private static let shellStartupNames: Set<String> = [
        ".zshrc", ".zprofile", ".zshenv",
        ".bashrc", ".bash_profile", ".profile",
        ".envrc", ".direnvrc",
    ]

    /// Git paths that live outside any `.git` segment (worktrees, submodules).
    private let resolvedGitPaths: [(segments: [String], kind: ExecutableArtifactKind, isDirectory: Bool)]
    private let trustStoreSegments: [String]
    private let policyFilename: String

    public init(
        projectRoot: URL,
        gitResolver: GitRepositoryResolver = GitRepositoryResolver(),
        trustStoreRoot: URL = LocalStoreDirectory.defaultURL()
    ) {
        let root = projectRoot.standardizedFileURL
        // Resolved from the filesystem rather than `git rev-parse`: this runs on
        // every gated tool call, and a subprocess costs more than every other
        // stage of the gate put together.
        let surfaces = gitResolver.localTrustSurfaces(in: root)
        var gitPaths: [(segments: [String], kind: ExecutableArtifactKind, isDirectory: Bool)] = []
        for url in Self.variants(of: surfaces.config) {
            gitPaths.append((Self.segments(of: url.path), .gitConfig, false))
        }
        for url in Self.variants(of: surfaces.hooks) {
            gitPaths.append((Self.segments(of: url.path), .gitHook, true))
        }
        self.resolvedGitPaths = gitPaths
        self.trustStoreSegments = Self.segments(of: trustStoreRoot.standardizedFileURL.path)
        self.policyFilename = Self.normalize(ProjectConfigLoader.filename)
    }

    public func classify(path: String, cwd: String? = nil) -> ExecutableArtifactMatch? {
        let absolute = URL(
            fileURLWithPath: PromptReadGate.resolveFilesystemPath(path, cwd: cwd)
        ).standardizedFileURL
        var candidates = [absolute]
        let resolved = absolute.resolvingSymlinksInPath()
        if resolved.path != absolute.path {
            candidates.append(resolved)
        }

        for candidate in candidates {
            if let kind = classify(segments: Self.segments(of: candidate.path)) {
                return ExecutableArtifactMatch(
                    path: absolute.path,
                    kind: kind,
                    enforcement: kind.enforcement
                )
            }
        }
        return nil
    }

    private func classify(segments: [String]) -> ExecutableArtifactKind? {
        guard let name = segments.last else { return nil }

        // Offsend's own trust anchor: an agent must not approve its own policy.
        if Self.isUnder(trustStoreSegments, segments) {
            return .offsendTrustStore
        }
        if name == policyFilename {
            return .offsendPolicy
        }

        // Anything inside a Git directory, at any depth. Nested repositories and
        // `.git` files carrying a `gitdir:` pointer are the same trust surface.
        if let gitIndex = segments.lastIndex(of: ".git") {
            let remainder = segments[segments.index(after: gitIndex)...]
            if remainder.isEmpty {
                return .gitDirectoryPointer
            }
            if remainder.contains("hooks") {
                return .gitHook
            }
            if name == "config" {
                return .gitConfig
            }
            return .gitDirectoryPointer
        }
        for entry in resolvedGitPaths {
            if entry.isDirectory ? Self.isUnder(entry.segments, segments) : entry.segments == segments {
                return entry.kind
            }
        }
        if name == ".gitconfig" || Self.hasSuffix([".config", "git", "config"], segments) {
            return .gitConfig
        }

        if let pair = Self.lastPair(segments), Self.editorHookPairs.contains(pair) {
            return .editorHookConfig
        }
        if Self.hasSuffix([".vscode", "tasks.json"], segments)
            || Self.hasSuffix([".vscode", "launch.json"], segments) {
            return .editorTaskConfig
        }
        if Self.hasSuffix([".vscode", "settings.json"], segments) || name.hasSuffix(".code-workspace") {
            return .editorSettings
        }

        if Self.shellStartupNames.contains(name)
            || Self.hasSuffix([".config", "fish", "config.fish"], segments)
            || Self.hasSuffix([".config", "direnv", "direnvrc"], segments) {
            return .shellStartupConfig
        }

        // Writing anything into an SSH directory can hand the host a new key or
        // a `ProxyCommand` that runs on the next connection.
        if segments.dropLast().contains(".ssh") {
            return .sshConfig
        }
        if segments.contains("launchagents") || segments.contains("launchdaemons") {
            return .launchAgent
        }

        if name.hasSuffix(".pth"), segments.contains("site-packages") {
            return .pythonStartupHook
        }
        if name == "sitecustomize.py" || name == "usercustomize.py" {
            return .pythonStartupHook
        }
        if segments.dropLast().last == "bin",
           name.hasPrefix("python") || name.hasPrefix("activate") {
            return .virtualEnvironmentInterpreter
        }
        if name == "pyvenv.cfg" {
            return .virtualEnvironmentInterpreter
        }

        return nil
    }

    // MARK: - Path normalization

    /// Case-folded, NFC-normalized path segments. APFS is case- and
    /// normalization-insensitive by default, so `.CURSOR` and `.cursor` name the
    /// same file and must classify the same way.
    static func segments(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map { normalize(String($0)) }
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// The URL as given plus its symlink-resolved form, when they differ.
    private static func variants(of url: URL) -> [URL] {
        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        return resolved.path == standardized.path ? [standardized] : [standardized, resolved]
    }

    private static func isUnder(_ directory: [String], _ candidate: [String]) -> Bool {
        guard !directory.isEmpty, candidate.count >= directory.count else { return false }
        return Array(candidate.prefix(directory.count)) == directory
    }

    private static func hasSuffix(_ suffix: [String], _ candidate: [String]) -> Bool {
        guard candidate.count >= suffix.count else { return false }
        return Array(candidate.suffix(suffix.count)) == suffix
    }

    private static func lastPair(_ segments: [String]) -> [String]? {
        guard segments.count >= 2 else { return nil }
        return Array(segments.suffix(2))
    }
}
