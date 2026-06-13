import Foundation

public enum HookType: String, Sendable, CaseIterable {
    case preCommit = "pre-commit"
}

public enum HookManagerError: Error, Equatable, Sendable {
    case notARepository(path: String)
    case hookAlreadyInstalled(path: String)
    case hookNotInstalled(path: String)
    case hookModified(path: String)
    case cliNotFound
    case writeFailed(path: String, message: String)
}

public struct HookInstallOptions: Sendable {
    public let repositoryPath: URL
    public let hookType: HookType
    public let failPolicy: CheckFailPolicy
    public let includePolicyCheck: Bool
    public let force: Bool
    public let cliExecutablePath: String

    public init(
        repositoryPath: URL,
        hookType: HookType = .preCommit,
        failPolicy: CheckFailPolicy = .block,
        includePolicyCheck: Bool = false,
        force: Bool = false,
        cliExecutablePath: String
    ) {
        self.repositoryPath = repositoryPath
        self.hookType = hookType
        self.failPolicy = failPolicy
        self.includePolicyCheck = includePolicyCheck
        self.force = force
        self.cliExecutablePath = cliExecutablePath
    }
}

public struct HookManager: Sendable {
    private let fileManager: FileManager
    private let gitResolver: GitRepositoryResolver

    public init(
        fileManager: FileManager = .default,
        gitResolver: GitRepositoryResolver = GitRepositoryResolver()
    ) {
        self.fileManager = fileManager
        self.gitResolver = gitResolver
    }

    public func install(_ options: HookInstallOptions) throws -> URL {
        let repositoryRoot = try resolveRepositoryRoot(startingAt: options.repositoryPath)
        let hookURL = hookFileURL(in: repositoryRoot, hookType: options.hookType)

        if fileManager.fileExists(atPath: hookURL.path) {
            let existing = try String(contentsOf: hookURL, encoding: .utf8)
            if Self.isManagedHookScript(existing) {
                // Reinstall managed hook.
            } else if options.force {
                // Overwrite foreign hook when forced.
            } else {
                throw HookManagerError.hookAlreadyInstalled(path: hookURL.path)
            }
        }

        let script = makeHookScript(options: options)
        do {
            try fileManager.createDirectory(
                at: hookURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try script.write(to: hookURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookURL.path)
        } catch {
            throw HookManagerError.writeFailed(path: hookURL.path, message: error.localizedDescription)
        }

        return hookURL
    }

    public func uninstall(
        repositoryPath: URL,
        hookType: HookType = .preCommit,
        force: Bool = false
    ) throws {
        let repositoryRoot = try resolveRepositoryRoot(startingAt: repositoryPath)
        let hookURL = hookFileURL(in: repositoryRoot, hookType: hookType)

        guard fileManager.fileExists(atPath: hookURL.path) else {
            throw HookManagerError.hookNotInstalled(path: hookURL.path)
        }

        let existing = try String(contentsOf: hookURL, encoding: .utf8)
        guard Self.isManagedHookScript(existing) else {
            if force {
                try fileManager.removeItem(at: hookURL)
                return
            }
            throw HookManagerError.hookModified(path: hookURL.path)
        }

        try fileManager.removeItem(at: hookURL)
    }

    public func isInstalled(repositoryPath: URL, hookType: HookType = .preCommit) throws -> Bool {
        try status(repositoryPath: repositoryPath, hookType: hookType).state == .installed
    }

    public func status(
        repositoryPath: URL,
        hookType: HookType = .preCommit,
        projectConfigLoader: ProjectConfigLoader = ProjectConfigLoader()
    ) throws -> HookStatusReport {
        let repositoryRoot = try resolveRepositoryRoot(startingAt: repositoryPath)
        let hookURL = hookFileURL(in: repositoryRoot, hookType: hookType)
        let configURL = projectConfigLoader.configURL(for: repositoryRoot)?.path

        guard fileManager.fileExists(atPath: hookURL.path) else {
            return HookStatusReport(
                repositoryPath: repositoryRoot.path,
                hookType: hookType,
                hookPath: hookURL.path,
                state: .notInstalled,
                projectConfigPath: configURL
            )
        }

        let contents = try String(contentsOf: hookURL, encoding: .utf8)
        let state: HookInstallationState = Self.isManagedHookScript(contents)
            ? .installed
            : .modified

        return HookStatusReport(
            repositoryPath: repositoryRoot.path,
            hookType: hookType,
            hookPath: hookURL.path,
            state: state,
            scriptPreview: contents,
            projectConfigPath: configURL
        )
    }

    public func makeHookScript(options: HookInstallOptions) -> String {
        var arguments = ["check", "--staged", "--fail-on", options.failPolicy.rawValue]
        if options.includePolicyCheck {
            arguments.append("--policy")
        }

        let quotedArguments = arguments.map(Self.shellQuote).joined(separator: " ")

        return """
        #!/bin/sh
        \(OffsendCLILocator.managedHookMarker) \(OffsendCLILocator.managedHookVersion)
        OFFSEND_BIN=\(Self.shellQuote(options.cliExecutablePath))
        if [ ! -x "$OFFSEND_BIN" ]; then
          OFFSEND_BIN="$(command -v offsend 2>/dev/null || true)"
        fi
        if [ -z "$OFFSEND_BIN" ]; then
          echo "offsend: executable not found; reinstall the hook with 'offsend hook install' or bypass with 'git commit --no-verify'" >&2
          exit 2
        fi
        exec "$OFFSEND_BIN" \(quotedArguments)
        """
    }

    /// A hook counts as Offsend-managed only when the marker appears in the
    /// leading lines, so foreign scripts that merely mention the marker are
    /// never overwritten or removed.
    static func isManagedHookScript(_ contents: String) -> Bool {
        contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(2)
            .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(OffsendCLILocator.managedHookMarker) }
    }

    private func resolveRepositoryRoot(startingAt path: URL) throws -> URL {
        do {
            return try gitResolver.repositoryRoot(startingAt: path)
        } catch let error as GitRepositoryError {
            switch error {
            case .notARepository(let path):
                throw HookManagerError.notARepository(path: path)
            default:
                throw error
            }
        }
    }

    private func hookFileURL(in repositoryRoot: URL, hookType: HookType) -> URL {
        gitResolver.hooksDirectory(in: repositoryRoot)
            .appendingPathComponent(hookType.rawValue)
    }

    private static func shellQuote(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_./:-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
