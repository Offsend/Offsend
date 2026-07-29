import ArgumentParser
import Darwin
import Foundation
import OffsendRuntime

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Launch an AI editor under the sandbox from .offsend.yml.",
        discussion: """
        Starts cursor, claude, or codex. When sandbox.enabled is true and nono \
        is installed, Claude Code / Codex are wrapped with `nono run …`; \
        otherwise the bare binary (or Cursor via open) is launched. Does not \
        trust policy — run `offsend policy trust` separately after reviewing \
        .offsend.yml.
        """
    )

    @Argument(help: "Editor to launch: cursor, claude, or codex.")
    var editor: String

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    @Flag(
        name: .long,
        help: "Run sandbox sync for this editor before launch (writes nono profile / editor sandbox config)."
    )
    var sync = false

    @Argument(
        parsing: .captureForPassthrough,
        help: "Arguments forwarded to the editor (after --)."
    )
    var agentArguments: [String] = []

    mutating func run() throws {
        let target: AIEditorHookTarget
        guard let parsed = AIEditorHookTarget(rawValue: editor.lowercased()),
              parsed != .windsurf else {
            CLIError.exit(
                .error,
                message: SandboxLaunch.LaunchError.unsupportedTarget(editor).errorDescription
                    ?? "Unsupported editor."
            )
        }
        target = parsed

        let directory = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        let config = (try? ProjectConfigLoader().load(from: directory)) ?? nil
        let sandboxEnabled = config?.sandbox?.enabled == true
        let nonoAvailable = SandboxMechanismResolver.nonoAvailable()

        if sync {
            try syncSandbox(
                repositoryURL: directory,
                config: config,
                target: target
            )
        }

        let forwarded = agentArguments.drop(while: { $0 == "--" }).map { String($0) }
        let invocation: SandboxLaunch.Invocation
        do {
            invocation = try SandboxLaunch.invocation(
                target: target,
                sandboxEnabled: sandboxEnabled,
                nonoAvailable: nonoAvailable,
                agentArguments: forwarded,
                openPath: target == .cursor ? directory.path : nil
            )
        } catch let error as SandboxLaunch.LaunchError {
            CLIError.exit(.error, message: error.localizedDescription)
        }

        if invocation.usesNono, let relative = invocation.profileRelativePath {
            let profileURL = directory.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: profileURL.path) else {
                CLIError.exit(
                    .error,
                    message: SandboxLaunch.LaunchError.missingNonoProfile(
                        path: "./\(relative)"
                    ).localizedDescription
                )
            }
            if let pack = NonoPackProbe().probe(target: target), !pack.isSatisfied {
                CLIError.exit(
                    .error,
                    message: SandboxLaunch.LaunchError.missingNonoPack(
                        message: pack.missingMessage
                    ).localizedDescription
                )
            }
        }

        let programPath = resolveProgram(invocation.program)
        guard let programPath else {
            if invocation.usesNono {
                CLIError.exit(
                    .error,
                    message: "Could not find `nono` on PATH. Install it (`brew install nono`) "
                        + "or unset sandbox.enabled to launch without a wrapper."
                )
            }
            CLIError.exit(
                .error,
                message: SandboxLaunch.LaunchError.missingBinary(invocation.program).localizedDescription
            )
        }

        let ui = CLIText(useColor: CLIColor.enabled(for: .text))
        if let mechanism = invocation.mechanism {
            FileHandle.standardError.write(
                Data("\(ui.hint("sandbox: \(mechanism.rawValue)"))\n".utf8)
            )
        } else {
            FileHandle.standardError.write(
                Data("\(ui.hint("sandbox: off (launching without nono)"))\n".utf8)
            )
        }
        FileHandle.standardError.write(Data("\(ui.hint(invocation.display))\n".utf8))

        try execReplacement(
            program: programPath,
            arguments: invocation.arguments,
            directory: directory
        )
    }

    private func syncSandbox(
        repositoryURL: URL,
        config: OffsendProjectConfig?,
        target: AIEditorHookTarget
    ) throws {
        let report = SandboxSyncService().run(
            repositoryURL: repositoryURL,
            config: config,
            targets: [target]
        )
        let ui = CLIText(useColor: CLIColor.enabled(for: .text))
        if !report.enabled {
            print(ui.hint("sandbox sync skipped (sandbox.enabled is not true)"))
            return
        }
        for change in report.changes where change.kind != .unchanged {
            print(ui.ok("\(change.kind.rawValue) \(change.relativePath)"))
        }
        for step in report.manualSteps {
            print(ui.hint(step))
        }
        for error in report.errors {
            print(ui.fail(error))
        }
        if !report.errors.isEmpty {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }

    private func resolveProgram(_ program: String) -> String? {
        if program.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: program) ? program : nil
        }
        return ExecutableLocator.which(program)
    }

    /// Replace this process with the editor so signals and stdin behave like a
    /// direct launch. Falls back to a child process if `exec` is unavailable.
    private func execReplacement(
        program: String,
        arguments: [String],
        directory: URL
    ) throws {
        FileManager.default.changeCurrentDirectoryPath(directory.path)

        #if os(macOS) || os(Linux)
        let argv = [program] + arguments
        let cArgs = argv.map { strdup($0) } + [nil]
        defer {
            for pointer in cArgs where pointer != nil {
                free(pointer)
            }
        }
        execv(program, cArgs)
        // execv only returns on failure.
        CLIError.exit(
            .error,
            message: "Failed to exec \(program): \(String(cString: strerror(errno)))"
        )
        #else
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ExitCode(process.terminationStatus)
        }
        #endif
    }
}
