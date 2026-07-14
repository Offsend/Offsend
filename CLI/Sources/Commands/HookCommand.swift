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
        abstract: "Install an Offsend-managed git hook or AI-editor prompt hook."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    @Option(
        name: .long,
        help: "Install target: git (default), cursor, claude, windsurf, codex, or all (AI targets)."
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
        name: .long,
        help: "Also install optional file-read path gates (Cursor beforeReadFile / Claude PreToolUse Read)."
    )
    var withReadGate = false

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

        if let target, target != "git" {
            let aiTargets: [AIEditorHookTarget]
            if target == "all" {
                aiTargets = Array(AIEditorHookTarget.allCases)
            } else {
                aiTargets = [CLIParse.aiEditorHookTarget(target)]
            }
            let policy = hookPolicy.map { CLIParse.checkHookPolicy($0) }
            let installer = AIEditorHookInstaller()
            let readGateSupported: Set<AIEditorHookTarget> = [.cursor, .claude]
            if withReadGate {
                let unsupported = aiTargets.filter { !readGateSupported.contains($0) }
                for skipped in unsupported {
                    fputs(
                        "warning: --with-read-gate is not supported for \(skipped.rawValue); installing prompt hook only.\n",
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
                        hookPolicy: policy,
                        force: force,
                        withReadGate: withReadGate
                    )
                    print(
                        "Installed \(result.target.rawValue) hook (\(result.hookPolicy.rawValue)) at \(result.configPath)"
                    )
                    print("Wrapper: \(result.wrapperPath)")
                    if let readPath = result.readWrapperPath {
                        print("Read gate: \(readPath)")
                    }
                    print("Command: \(result.command)")
                }
                print("Next: commit `.offsend/hooks/` and the editor config to share with the team.")
            } catch let error as AIEditorHookInstallerError {
                CLIError.exit(.error, message: error.localizedDescription)
            }
            return
        }

        if withReadGate {
            CLIError.exit(.error, message: "--with-read-gate requires --target cursor|claude|all.")
        }

        if hookPolicy != nil {
            CLIError.exit(
                .error,
                message: "--hook-policy is only valid with --target cursor|claude|windsurf|codex|all."
            )
        }

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
            CLIError.exit(for: error)
        }
    }
}

struct HookUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove an Offsend-managed git or AI-editor hook."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    @Option(
        name: .long,
        help: "Uninstall target: git (default), cursor, claude, windsurf, codex, or all (AI targets)."
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
}

struct HookStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show Offsend git or AI-editor hook status for a repository."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    @Option(
        name: .long,
        help: "Status target: git (default), cursor, claude, windsurf, codex, or all (AI targets)."
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
}
