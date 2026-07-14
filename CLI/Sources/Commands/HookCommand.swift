import ArgumentParser
import Foundation
import OffsendRuntime

struct Hook: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install or remove Offsend git and AI-editor hooks.",
        subcommands: [HookInstall.self, HookUninstall.self, HookStatus.self]
    )
}

struct HookInstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install Offsend-managed git and AI-editor hooks.",
        discussion: "Without --target, installs the git pre-commit hook plus AI-editor hooks "
            + "for detected editors (Cursor and Claude always; Windsurf/Codex when present)."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    @Option(
        name: .long,
        help: "Install target: git, cursor, claude, windsurf, codex, or all (AI targets). Default: git plus detected AI editors."
    )
    var target: String?

    @Option(name: .long, help: "Git hook type to install (pre-commit). Ignored for AI targets.")
    var type: String?

    @Option(name: .long, help: "Exit policy for git hooks (block, warn, none).")
    var failOn: String?

    @Option(
        name: .long,
        help: "Policy for AI-editor hooks (advise, soft-block, block). block = soft-block plus seal-copy."
    )
    var hookPolicy: String?

    @Flag(name: .long, help: "Include workspace policy checks in the git hook.")
    var policy = false

    @Flag(
        name: .long,
        help: "Overwrite a non-Offsend git hook or AI wrapper. Managed hooks refresh without this flag."
    )
    var force = false

    @Flag(
        name: [.customLong("read-gate"), .customLong("with-read-gate")],
        inversion: .prefixedNo,
        help: "File-read gates — sensitive paths + secret content scan (Cursor beforeReadFile / Claude PreToolUse Read). On by default for cursor/claude; disable with --no-read-gate."
    )
    var readGate: Bool?

    @Flag(
        name: .customLong("shell-gate"),
        help: "Also gate shell commands touching sensitive paths (Cursor beforeShellExecution / Claude PreToolUse Bash). Findings ask for confirmation. Opt-in."
    )
    var shellGate = false

    @Option(name: .long, help: "Path to the offsend executable used by the hook.")
    var cliPath: String?

    mutating func run() throws {
        let repositoryURL = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        guard let executable = cliPath ?? OffsendCLILocator.resolvedExecutablePath() else {
            CLIError.exit(.error, message: "Could not locate the offsend executable. Pass --cli-path.")
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            CLIError.exit(.error, message: "Not an executable file: \(executable)")
        }

        let installGit: Bool
        let aiTargets: [AIEditorHookTarget]
        switch target {
        case nil:
            // Default: full protection — git hook plus hooks for detected editors.
            installGit = true
            aiTargets = AIEditorHookTarget.detectedTargets(
                repositoryPath: repositoryURL,
                homeDirectory: defaultHomeDirectory()
            )
        case "git":
            installGit = true
            aiTargets = []
        case "all":
            installGit = false
            aiTargets = Array(AIEditorHookTarget.allCases)
        case .some(let value):
            installGit = false
            aiTargets = [CLIParse.aiEditorHookTarget(value)]
        }

        if aiTargets.isEmpty {
            if readGate != nil {
                CLIError.exit(.error, message: "--read-gate/--no-read-gate requires an AI-editor target.")
            }
            if shellGate {
                CLIError.exit(.error, message: "--shell-gate requires an AI-editor target.")
            }
            if hookPolicy != nil {
                CLIError.exit(.error, message: "--hook-policy requires an AI-editor target.")
            }
        }

        if installGit {
            // In the combined default run, a git failure downgrades to a warning
            // so AI-editor protection still gets installed.
            installGitHook(
                repositoryURL: repositoryURL,
                executable: executable,
                tolerateFailure: !aiTargets.isEmpty
            )
        }
        if !aiTargets.isEmpty {
            installAIHooks(aiTargets, repositoryURL: repositoryURL, executable: executable)
        }
    }

    private func installGitHook(repositoryURL: URL, executable: String, tolerateFailure: Bool) {
        if let type {
            _ = CLIParse.hookType(type)
        }
        let validatedFailOn = CLIParse.failPolicy(failOn)

        let projectConfig = CLIParse.projectConfig(from: repositoryURL)
        let resolved = OptionsResolver.resolveHookOptions(
            overrides: CLIHookOverrides(
                hookType: type,
                policySpecified: policy,
                policyValue: policy,
                failOn: validatedFailOn
            ),
            projectConfig: projectConfig
        )

        let manager = HookManager()
        do {
            let hookURL = try manager.install(
                HookInstallOptions(
                    repositoryPath: repositoryURL,
                    hookType: resolved.hookType,
                    failPolicy: resolved.failPolicy,
                    includePolicyCheck: resolved.includePolicyCheck,
                    force: force,
                    cliExecutablePath: executable
                )
            )
            print("Installed \(resolved.hookType.rawValue) hook at \(hookURL.path)")
        } catch let error as HookManagerError {
            guard tolerateFailure else {
                CLIError.exit(for: error)
            }
            fputs("warning: git hook skipped: \(CLIError.message(for: error))\n", stderr)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }
    }

    private func installAIHooks(
        _ aiTargets: [AIEditorHookTarget],
        repositoryURL: URL,
        executable: String
    ) {
        let policyOverride = hookPolicy.map { CLIParse.checkHookPolicy($0) }
        let installer = AIEditorHookInstaller()
        let gateSupported: Set<AIEditorHookTarget> = [.cursor, .claude]
        // Read-gate is on by default for supported targets; --no-read-gate opts out.
        let enableReadGate = readGate ?? true
        if readGate == true {
            let unsupported = aiTargets.filter { !gateSupported.contains($0) }
            for skipped in unsupported {
                fputs(
                    "warning: --read-gate is not supported for \(skipped.rawValue); installing prompt hook only.\n",
                    stderr
                )
            }
        }
        if shellGate {
            let unsupported = aiTargets.filter { !gateSupported.contains($0) }
            for skipped in unsupported {
                fputs(
                    "warning: --shell-gate is not supported for \(skipped.rawValue); installing prompt hook only.\n",
                    stderr
                )
            }
        }
        do {
            for aiTarget in aiTargets {
                let result = try installer.install(
                    target: aiTarget,
                    repositoryPath: repositoryURL,
                    cliExecutablePath: executable,
                    hookPolicy: policyOverride,
                    force: force,
                    withReadGate: enableReadGate,
                    withShellGate: shellGate
                )
                print(
                    "Installed \(result.target.rawValue) hook (\(result.hookPolicy.rawValue)) at \(result.configPath)"
                )
                print("Wrapper: \(result.wrapperPath)")
                if let readPath = result.readWrapperPath {
                    print("Read gate: \(readPath)")
                }
                if let shellPath = result.shellWrapperPath {
                    print("Shell gate: \(shellPath)")
                }
                print("Command: \(result.command)")
            }
            print("Next: commit `.offsend/hooks/` and the editor config to share with the team.")
        } catch let error as AIEditorHookInstallerError {
            CLIError.exit(.error, message: error.localizedDescription)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
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

struct HookUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove Offsend-managed git and AI-editor hooks.",
        discussion: "Without --target, removes every Offsend-managed hook (git plus AI editors)."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    @Option(
        name: .long,
        help: "Uninstall target: git, cursor, claude, windsurf, codex, or all (AI targets). Default: every Offsend-managed hook."
    )
    var target: String?

    @Option(name: .long, help: "Git hook type to remove (pre-commit).")
    var type: String = HookType.preCommit.rawValue

    @Flag(name: .long, help: "Remove the git hook file even if it is not Offsend-managed.")
    var force = false

    mutating func run() throws {
        let repositoryURL = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        if target == nil {
            removeAllManagedHooks(repositoryURL: repositoryURL)
            return
        }

        if let target, target != "git" {
            let aiTargets: [AIEditorHookTarget]
            if target == "all" {
                aiTargets = Array(AIEditorHookTarget.allCases)
            } else {
                aiTargets = [CLIParse.aiEditorHookTarget(target)]
            }
            let installer = AIEditorHookInstaller()
            do {
                for aiTarget in aiTargets {
                    let isInstalled = installer.status(
                        target: aiTarget,
                        repositoryPath: repositoryURL
                    ).installed
                    if target == "all", !isInstalled {
                        continue
                    }
                    try installer.uninstall(
                        target: aiTarget,
                        repositoryPath: repositoryURL
                    )
                    print("Removed \(aiTarget.rawValue) AI-editor hook.")
                }
            } catch let error as AIEditorHookInstallerError {
                CLIError.exit(.error, message: error.localizedDescription)
            }
            return
        }

        let hookType = CLIParse.hookType(type)
        let manager = HookManager()
        do {
            try manager.uninstall(repositoryPath: repositoryURL, hookType: hookType, force: force)
            print("Removed \(hookType.rawValue) hook.")
        } catch let error as HookManagerError {
            CLIError.exit(for: error)
        }
    }

    /// Best-effort removal of every Offsend-managed hook. Missing hooks are
    /// skipped; a manually modified git hook is left in place with a warning.
    private func removeAllManagedHooks(repositoryURL: URL) {
        var removedAny = false
        let hookType = CLIParse.hookType(type)
        let manager = HookManager()
        do {
            try manager.uninstall(repositoryPath: repositoryURL, hookType: hookType, force: force)
            print("Removed \(hookType.rawValue) hook.")
            removedAny = true
        } catch let error as HookManagerError {
            switch error {
            case .hookNotInstalled, .notARepository:
                break
            case .hookModified:
                fputs("warning: git hook skipped: \(CLIError.message(for: error))\n", stderr)
            default:
                CLIError.exit(for: error)
            }
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }

        let installer = AIEditorHookInstaller()
        for aiTarget in AIEditorHookTarget.allCases {
            guard installer.status(target: aiTarget, repositoryPath: repositoryURL).installed else {
                continue
            }
            do {
                try installer.uninstall(target: aiTarget, repositoryPath: repositoryURL)
                print("Removed \(aiTarget.rawValue) AI-editor hook.")
                removedAny = true
            } catch let error as AIEditorHookInstallerError {
                CLIError.exit(.error, message: error.localizedDescription)
            } catch {
                CLIError.exit(.error, message: error.localizedDescription)
            }
        }

        if !removedAny {
            print("No Offsend-managed hooks found.")
        }
    }
}

struct HookStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show Offsend git and AI-editor hook status for a repository.",
        discussion: "Without --target, shows the git hook and every AI-editor target."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    @Option(
        name: .long,
        help: "Status target: git, cursor, claude, windsurf, codex, or all (AI targets). Default: git plus all AI targets."
    )
    var target: String?

    @Option(name: .long, help: "Git hook type to inspect (pre-commit).")
    var type: String = HookType.preCommit.rawValue

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    mutating func run() throws {
        let outputFormat = CLIParse.outputFormat(format)
        let repositoryURL = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        if target == nil {
            try runCombinedStatus(repositoryURL: repositoryURL, outputFormat: outputFormat)
            return
        }

        if let target, target != "git" {
            let aiTargets: [AIEditorHookTarget]
            if target == "all" {
                aiTargets = Array(AIEditorHookTarget.allCases)
            } else {
                aiTargets = [CLIParse.aiEditorHookTarget(target)]
            }
            let installer = AIEditorHookInstaller()
            var anyBroken = false
            var statuses: [(target: AIEditorHookTarget, installed: Bool, broken: Bool, configPath: String)] = []

            for aiTarget in aiTargets {
                let status = installer.status(target: aiTarget, repositoryPath: repositoryURL)
                statuses.append((aiTarget, status.installed, status.broken, status.configPath))
                if status.broken {
                    anyBroken = true
                }
            }

            switch outputFormat {
            case .text:
                for entry in statuses {
                    if entry.broken {
                        print("! \(entry.target.rawValue): broken (\(entry.configPath))")
                    } else {
                        let marker = entry.installed ? "✓" : "✗"
                        print(
                            "\(marker) \(entry.target.rawValue): \(entry.installed ? "installed" : "not installed") (\(entry.configPath))"
                        )
                    }
                }
            case .json:
                let targets: [[String: Any]] = statuses.map { entry in
                    [
                        "target": entry.target.rawValue,
                        "installed": entry.installed,
                        "broken": entry.broken,
                        "configPath": entry.configPath,
                    ]
                }
                let payload: [String: Any] = ["targets": targets]
                if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                   let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
            }

            if target != "all" {
                let status = statuses[0]
                if !status.installed || status.broken {
                    throw ExitCode(OffsendExitCode.hookState.rawValue)
                }
            } else if anyBroken {
                throw ExitCode(OffsendExitCode.hookState.rawValue)
            }
            return
        }

        let hookType = CLIParse.hookType(type)
        let manager = HookManager()
        do {
            let report = try manager.status(repositoryPath: repositoryURL, hookType: hookType)
            print(HookStatusReporter().render(report, format: outputFormat))

            if report.state != .installed {
                throw ExitCode(OffsendExitCode.hookState.rawValue)
            }
        } catch let error as HookManagerError {
            CLIError.exit(for: error)
        }
    }

    /// Combined overview: git hook plus every AI-editor target.
    /// Exits `3` when the git hook is not installed or any AI hook is broken.
    private func runCombinedStatus(repositoryURL: URL, outputFormat: CheckOutputFormat) throws {
        let hookType = CLIParse.hookType(type)
        let manager = HookManager()

        let gitState: String
        let gitPath: String
        do {
            let report = try manager.status(repositoryPath: repositoryURL, hookType: hookType)
            gitState = report.state.rawValue
            gitPath = report.hookPath
        } catch HookManagerError.notARepository {
            gitState = "not-a-repository"
            gitPath = repositoryURL.path
        } catch let error as HookManagerError {
            CLIError.exit(for: error)
        }
        let gitOK = gitState == HookInstallationState.installed.rawValue

        let installer = AIEditorHookInstaller()
        let statuses = AIEditorHookTarget.allCases.map { aiTarget in
            (target: aiTarget, status: installer.status(target: aiTarget, repositoryPath: repositoryURL))
        }
        let anyBroken = statuses.contains { $0.status.broken }

        switch outputFormat {
        case .text:
            print("\(gitOK ? "✓" : "✗") git (\(hookType.rawValue)): \(gitState) (\(gitPath))")
            for entry in statuses {
                if entry.status.broken {
                    print("! \(entry.target.rawValue): broken (\(entry.status.configPath))")
                } else {
                    let marker = entry.status.installed ? "✓" : "✗"
                    print(
                        "\(marker) \(entry.target.rawValue): \(entry.status.installed ? "installed" : "not installed") (\(entry.status.configPath))"
                    )
                }
            }
        case .json:
            let targets: [[String: Any]] = statuses.map { entry in
                [
                    "target": entry.target.rawValue,
                    "installed": entry.status.installed,
                    "broken": entry.status.broken,
                    "configPath": entry.status.configPath,
                ]
            }
            let payload: [String: Any] = [
                "git": [
                    "hookType": hookType.rawValue,
                    "path": gitPath,
                    "status": gitState,
                ],
                "targets": targets,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        }

        if !gitOK || anyBroken {
            throw ExitCode(OffsendExitCode.hookState.rawValue)
        }
    }
}
