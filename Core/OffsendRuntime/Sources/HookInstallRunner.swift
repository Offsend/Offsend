import Foundation

/// Shared install logic for `hook install` and `offsend sync`: git pre-commit
/// hook plus AI-editor hooks, returning structured outcomes so callers can
/// render text or JSON.
public enum HookInstallRunner {
    public struct GitOutcome: Sendable {
        public let hookType: HookType
        /// nil when the install was skipped (tolerated foreign hook).
        public let hookURL: URL?
        public let warning: String?
    }

    public struct AIHookFailure: Error {
        public let target: AIEditorHookTarget
        public let message: String
    }

    public struct AIOutcome: Sendable {
        public let results: [AIEditorHookInstallResult]
        public let publishHooks: Bool
        public let excludeUpdated: Bool
        public let warnings: [String]
    }

    /// Installs the git hook. When `tolerateFailure` is true a `HookManagerError`
    /// (e.g. a foreign pre-commit hook) becomes a warning outcome instead of an
    /// error, so AI-editor protection still gets installed.
    public static func installGitHook(
        repositoryURL: URL,
        executable: String,
        overrides: CLIHookOverrides = CLIHookOverrides(),
        force: Bool = false,
        tolerateFailure: Bool
    ) throws -> GitOutcome {
        let projectConfig = try ProjectConfigLoader().load(from: repositoryURL)
        let resolved = OptionsResolver.resolveHookOptions(
            overrides: overrides,
            projectConfig: projectConfig
        )

        do {
            let hookURL = try HookManager().install(
                HookInstallOptions(
                    repositoryPath: repositoryURL,
                    hookType: resolved.hookType,
                    failPolicy: resolved.failPolicy,
                    includePolicyCheck: resolved.includePolicyCheck,
                    force: force,
                    cliExecutablePath: executable
                )
            )
            return GitOutcome(hookType: resolved.hookType, hookURL: hookURL, warning: nil)
        } catch let error as HookManagerError {
            guard tolerateFailure else { throw error }
            return GitOutcome(
                hookType: resolved.hookType,
                hookURL: nil,
                warning: "git hook skipped: \(message(for: error))"
            )
        }
    }

    /// Installs AI-editor hooks for the given targets, honoring `hooks.publish`
    /// from `.offsend.yml` (`portableWrappers`). When publish is false, keeps
    /// the editor configs out of git via the local exclude. Calls `onInstall`
    /// after each target so text callers can stream output; throws
    /// `AIHookFailure` on the first failing target.
    public static func installAIHooks(
        _ aiTargets: [AIEditorHookTarget],
        repositoryURL: URL,
        executable: String,
        hookPolicy: CheckHookPolicy? = nil,
        force: Bool = false,
        withReadGate: Bool = true,
        withShellGate: Bool = true,
        withMCPGate: Bool = true,
        withSubagentGate: Bool = true,
        onInstall: (AIEditorHookInstallResult) -> Void = { _ in }
    ) throws -> AIOutcome {
        let installer = AIEditorHookInstaller()
        let projectConfig = try ProjectConfigLoader().load(from: repositoryURL)
        let publishHooks = OptionsResolver.resolveHookOptions(
            overrides: CLIHookOverrides(),
            projectConfig: projectConfig
        ).publishHooks

        var results: [AIEditorHookInstallResult] = []
        for aiTarget in aiTargets {
            do {
                let result = try installer.install(
                    target: aiTarget,
                    repositoryPath: repositoryURL,
                    cliExecutablePath: executable,
                    hookPolicy: hookPolicy,
                    force: force,
                    withReadGate: withReadGate,
                    withShellGate: withShellGate,
                    withMCPGate: withMCPGate,
                    withSubagentGate: withSubagentGate,
                    portableWrappers: publishHooks
                )
                results.append(result)
                onInstall(result)
            } catch {
                throw AIHookFailure(target: aiTarget, message: error.localizedDescription)
            }
        }

        var warnings: [String] = []
        var excludeUpdated = false
        if !publishHooks, !aiTargets.isEmpty {
            // Exclude only what this run installed; merge keeps entries from
            // earlier installs of other targets.
            let repoRootPrefix = repositoryURL.standardizedFileURL.path + "/"
            let configRelativePaths = aiTargets.map { target in
                let path = installer.configURL(for: target, repositoryPath: repositoryURL).path
                return path.hasPrefix(repoRootPrefix) ? String(path.dropFirst(repoRootPrefix.count)) : path
            }
            let excludeReport = OffsendLocalGitExcludeService().upsertPatterns(
                OffsendLocalGitExcludeService.aiHookExcludePatterns(configRelativePaths: configRelativePaths),
                repositoryURL: repositoryURL,
                section: OffsendLocalGitExcludeService.hooksSection,
                merge: true
            )
            excludeUpdated = excludeReport.updated
            warnings.append(contentsOf: excludeReport.errors)
        }

        return AIOutcome(
            results: results,
            publishHooks: publishHooks,
            excludeUpdated: excludeUpdated,
            warnings: warnings
        )
    }

    private static func message(for error: HookManagerError) -> String {
        switch error {
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        case .hookAlreadyInstalled(let path):
            return "Hook already exists at \(path). Use --force to overwrite."
        case .hookNotInstalled(let path):
            return "No hook found at \(path)."
        case .hookModified(let path):
            return "Hook at \(path) was modified manually. Use --force to remove it."
        case .cliNotFound:
            return "Could not locate the offsend executable."
        case .writeFailed(let path, let details):
            return "Failed to write hook at \(path): \(details)"
        }
    }
}
