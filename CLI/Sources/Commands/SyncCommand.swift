import ArgumentParser
import Foundation
import OffsendRuntime

struct Sync: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Apply .offsend.yml: materialize AI ignore files and install hooks.",
        discussion: """
        The one post-clone command: materializes ignore.patterns from \
        .offsend.yml into every AI ignore file \
        and installs the git pre-commit hook plus AI-editor hooks for detected \
        editors. Idempotent — safe to re-run; an up-to-date repository is left \
        unchanged. Requires an existing .offsend.yml (run `offsend init` first).
        """
    )

    @Option(name: .long, help: "Project directory. Defaults to the current directory.")
    var path: String?

    @Flag(name: .customLong("no-hooks"), help: "Only materialize ignore files; skip hook installation.")
    var noHooks = false

    @Flag(name: .long, help: "Show what would change without writing. Hooks are not installed.")
    var dryRun = false

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    private enum HooksSection {
        case skipped(reason: String)
        case installed(
            git: HookInstallRunner.GitOutcome,
            targets: [(target: AIEditorHookTarget, result: AIEditorHookInstallResult?, error: String?)],
            publishHooks: Bool,
            excludeUpdated: Bool
        )
    }

    mutating func run() throws {
        let outputFormat = CLIParse.outputFormat(format)

        let context: OffsendRuntimeContext
        do {
            context = try OffsendRuntimeContext.load()
        } catch {
            CLIError.exit(.error, message: "Failed to load Offsend settings: \(error.localizedDescription)")
        }

        let directoryURL = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        let ignoreReport = OffsendIgnoreSyncService(context: context).run(
            directoryURL: directoryURL,
            dryRun: dryRun
        )

        var hookErrors: [String] = []
        let hooks: HooksSection
        if dryRun {
            hooks = .skipped(reason: "dry-run")
        } else if noHooks {
            hooks = .skipped(reason: "--no-hooks")
        } else if ignoreReport.hasErrors {
            hooks = .skipped(reason: "ignore sync failed")
        } else {
            hooks = installHooks(
                repositoryURL: URL(fileURLWithPath: ignoreReport.directoryPath),
                errors: &hookErrors
            )
        }

        let useColor = CLIColor.enabled(for: outputFormat)
        switch outputFormat {
        case .text:
            renderText(ignoreReport: ignoreReport, hooks: hooks, useColor: useColor)
        case .json:
            renderJSON(ignoreReport: ignoreReport, hooks: hooks)
        }

        if ignoreReport.hasErrors || !hookErrors.isEmpty {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }

    /// Git failures (e.g. a foreign pre-commit hook) downgrade to warnings so
    /// AI-editor protection still installs; AI-hook failures are collected as
    /// errors (exit 2).
    private func installHooks(repositoryURL: URL, errors: inout [String]) -> HooksSection {
        guard let executable = OffsendCLILocator.resolvedExecutablePath() else {
            errors.append("Could not locate the offsend executable. Run `offsend hook install --cli-path <path>`.")
            return .skipped(reason: "offsend executable not found")
        }

        let git: HookInstallRunner.GitOutcome
        do {
            git = try HookInstallRunner.installGitHook(
                repositoryURL: repositoryURL,
                executable: executable,
                tolerateFailure: true
            )
        } catch {
            // Unreachable with tolerateFailure, but keep the compiler honest.
            errors.append(error.localizedDescription)
            return .skipped(reason: "git hook install failed")
        }
        if let warning = git.warning {
            fputs("warning: \(warning)\n", stderr)
        }

        let aiTargets = AIEditorHookTarget.detectedTargets(
            repositoryPath: repositoryURL,
            homeDirectory: defaultHomeDirectory()
        )

        var targets: [(target: AIEditorHookTarget, result: AIEditorHookInstallResult?, error: String?)] = []
        var publishHooks = false
        var excludeUpdated = false
        do {
            let outcome = try HookInstallRunner.installAIHooks(
                aiTargets,
                repositoryURL: repositoryURL,
                executable: executable
            )
            targets = outcome.results.map { ($0.target, $0, nil) }
            publishHooks = outcome.publishHooks
            excludeUpdated = outcome.excludeUpdated
            for warning in outcome.warnings {
                fputs("warning: \(warning)\n", stderr)
            }
        } catch let failure as HookInstallRunner.AIHookFailure {
            targets.append((failure.target, nil, failure.message))
            errors.append("\(failure.target.rawValue): \(failure.message)")
        } catch {
            errors.append(error.localizedDescription)
        }

        return .installed(
            git: git,
            targets: targets,
            publishHooks: publishHooks,
            excludeUpdated: excludeUpdated
        )
    }

    private func renderText(ignoreReport: IgnoreSyncReport, hooks: HooksSection, useColor: Bool) {
        let ui = CLIText(useColor: useColor)
        let syncText = IgnoreSyncReporter().render(ignoreReport, format: .text, useColor: useColor)
        if !syncText.isEmpty {
            print(syncText)
        }

        switch hooks {
        case .skipped(let reason):
            print("")
            print(ui.hint("hooks: skipped (\(reason))"))
        case .installed(let git, let targets, let publishHooks, let excludeUpdated):
            print("")
            print(ui.section("Hooks"))
            if git.warning == nil, let hookURL = git.hookURL {
                print(ui.ok("git \(git.hookType.rawValue) hook (\(hookURL.path))"))
            }
            for entry in targets {
                if let result = entry.result {
                    print(ui.ok("\(result.target.rawValue) hook (\(result.hookPolicy.rawValue)) — \(result.configPath)"))
                } else if let error = entry.error {
                    print(ui.fail("\(entry.target.rawValue): \(error)"))
                }
            }
            if excludeUpdated {
                print(ui.hint("Updated local git exclude so AI hooks stay untracked."))
            }
            if publishHooks {
                print(ui.hint("hooks.publish: true — commit `.offsend/hooks/` and the editor config to share with the team."))
            }
        }
    }

    private func renderJSON(ignoreReport: IgnoreSyncReport, hooks: HooksSection) {
        var hooksPayload: [String: Any]
        switch hooks {
        case .skipped(let reason):
            hooksPayload = [
                "skipped": true,
                "reason": reason,
            ]
        case .installed(let git, let targets, let publishHooks, _):
            var gitPayload: [String: Any] = [
                "hookType": git.hookType.rawValue,
                "status": git.hookURL != nil ? "installed" : "skipped",
            ]
            if let hookURL = git.hookURL {
                gitPayload["path"] = hookURL.path
            }
            if let warning = git.warning {
                gitPayload["warning"] = warning
            }
            let targetPayloads: [[String: Any]] = targets.map { entry in
                if let result = entry.result {
                    return [
                        "target": result.target.rawValue,
                        "status": "installed",
                        "hookPolicy": result.hookPolicy.rawValue,
                        "configPath": result.configPath,
                    ]
                }
                return [
                    "target": entry.target.rawValue,
                    "status": "error",
                    "error": entry.error ?? "unknown error",
                ]
            }
            hooksPayload = [
                "skipped": false,
                "git": gitPayload,
                "targets": targetPayloads,
                "hooksPublish": publishHooks,
            ]
        }

        let payload: [String: Any] = [
            "directory": ignoreReport.directoryPath,
            "dryRun": ignoreReport.dryRun,
            "patterns": ignoreReport.patterns,
            "commitIgnoreFiles": ignoreReport.commitIgnoreFiles,
            "createdRelativePaths": ignoreReport.createdRelativePaths,
            "updatedRelativePaths": ignoreReport.updatedRelativePaths,
            "unchangedRelativePaths": ignoreReport.unchangedRelativePaths,
            "gitignoreUpdated": ignoreReport.gitignoreUpdated,
            "gitignorePath": ignoreReport.gitignorePath as Any,
            "excludeUpdated": ignoreReport.excludeUpdated,
            "excludePath": ignoreReport.excludePath as Any,
            "errors": ignoreReport.errors,
            "hooks": hooksPayload,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }
}

/// Prefers `$HOME` so tests and CI can point editor detection at a scratch directory.
private func defaultHomeDirectory() -> URL {
    if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
        return URL(fileURLWithPath: home)
    }
    return FileManager.default.homeDirectoryForCurrentUser
}
