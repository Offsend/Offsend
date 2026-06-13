import ArgumentParser
import Foundation
import OffsendRuntime

struct Hook: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install or remove Offsend git hooks.",
        subcommands: [HookInstall.self, HookUninstall.self, HookStatus.self]
    )
}

struct HookInstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install an Offsend-managed git hook."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    @Option(name: .long, help: "Hook type to install (pre-commit).")
    var type: String?

    @Option(name: .long, help: "Exit policy used by the installed hook (block, warn, none).")
    var failOn: String?

    @Flag(name: .long, help: "Include workspace policy checks in the hook.")
    var policy = false

    @Flag(name: .long, help: "Overwrite an existing non-Offsend hook.")
    var force = false

    @Option(name: .long, help: "Path to the offsend executable used by the hook.")
    var cliPath: String?

    mutating func run() throws {
        if let type {
            _ = CLIParse.hookType(type)
        }
        let validatedFailOn = CLIParse.failPolicy(failOn)

        let repositoryURL = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

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

        guard let executable = cliPath ?? OffsendCLILocator.resolvedExecutablePath() else {
            CLIError.exit(.error, message: "Could not locate the offsend executable. Pass --cli-path.")
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            CLIError.exit(.error, message: "Not an executable file: \(executable)")
        }

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
        abstract: "Remove an Offsend-managed git hook."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    @Option(name: .long, help: "Hook type to remove (pre-commit).")
    var type: String = HookType.preCommit.rawValue

    @Flag(name: .long, help: "Remove the hook file even if it is not Offsend-managed.")
    var force = false

    mutating func run() throws {
        let hookType = CLIParse.hookType(type)

        let repositoryURL = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

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
        abstract: "Show Offsend git hook status for a repository."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    @Option(name: .long, help: "Hook type to inspect (pre-commit).")
    var type: String = HookType.preCommit.rawValue

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    mutating func run() throws {
        let hookType = CLIParse.hookType(type)
        let outputFormat = CLIParse.outputFormat(format)

        let repositoryURL = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

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
