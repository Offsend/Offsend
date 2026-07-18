import ArgumentParser
import Foundation
import OffsendRuntime

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Guided project setup: doctor → init → protect → hooks → show.",
        discussion: """
        Interactive onboarding wizard. In a TTY, confirms each step. \
        Use --yes for non-interactive defaults (requires --template when init is needed).
        """
    )

    @Option(name: .long, help: "Project directory. Defaults to the current directory.")
    var path: String?

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Exclude template(s) for init when .offsend.yml is missing. Required with --yes."
    )
    var template: [String] = []

    @Flag(name: .long, help: "Run without prompts (CI-friendly). Requires --template when init is needed.")
    var yes = false

    @Flag(name: .customLong("skip-protect"), help: "Skip the protect step.")
    var skipProtect = false

    @Flag(name: .customLong("skip-hooks"), help: "Skip hook installation.")
    var skipHooks = false

    @Flag(name: .long, help: "Also protect recommended exposures during protect.")
    var includeRecommended = false

    @Flag(name: .customLong("ignore-commit"), help: "Pass --ignore-commit to init.")
    var ignoreCommit = false

    @Flag(name: .customLong("no-ignore-commit"), help: "Pass --no-ignore-commit to init.")
    var noIgnoreCommit = false

    @Flag(name: .customLong("hooks-publish"), help: "Pass --hooks-publish to init.")
    var hooksPublish = false

    @Flag(name: .customLong("no-hooks-publish"), help: "Pass --no-hooks-publish to init.")
    var noHooksPublish = false

    mutating func run() async throws {
        if ignoreCommit, noIgnoreCommit {
            CLIError.exit(.error, message: "Use either --ignore-commit or --no-ignore-commit, not both.")
        }
        if hooksPublish, noHooksPublish {
            CLIError.exit(.error, message: "Use either --hooks-publish or --no-hooks-publish, not both.")
        }

        let directoryURL = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL
        let directory = directoryURL.path
        let useColor = CLIColor.enabled(for: .text)
        let ui = CLIText(useColor: useColor)
        let interactive = !yes && CLIPrompt.isInteractiveTTY
        let totalSteps = 5

        print(ui.title("Offsend setup"))
        print(ui.hint(directory))

        // 1. Doctor
        CLIPrompt.step(current: 1, total: totalSteps, title: "Doctor")
        let doctor = OffsendDoctor().run()
        print(DoctorReporter().render(doctor, format: .text, useColor: useColor))
        if !doctor.isHealthy {
            CLIError.exit(.error, message: "Doctor reported failures. Fix them, then re-run offsend setup.")
        }

        // 2. Init
        CLIPrompt.step(current: 2, total: totalSteps, title: "Project config")
        let configURL = Init.configURL(forDirectory: path)
        let needsInit = !FileManager.default.fileExists(atPath: configURL.path)
        if needsInit {
            if interactive {
                guard CLIPrompt.yesNo(
                    question: "Create \(ProjectConfigLoader.filename)?",
                    hint: "Writes team policy and syncs AI ignore files.",
                    defaultYes: true
                ) else {
                    print(ui.warn("Skipped init — setup incomplete."))
                    return
                }
            } else if template.isEmpty {
                CLIError.exit(
                    .error,
                    message: "No \(ProjectConfigLoader.filename). Pass --template <stack> (and --yes for non-interactive)."
                )
            }

            var initArgs = ["init", "--path", directory, "--no-check"]
            for value in template {
                initArgs.append(contentsOf: ["--template", value])
            }
            if ignoreCommit { initArgs.append("--ignore-commit") }
            if noIgnoreCommit { initArgs.append("--no-ignore-commit") }
            if hooksPublish { initArgs.append("--hooks-publish") }
            if noHooksPublish { initArgs.append("--no-hooks-publish") }
            // In non-interactive --yes without ignore flags, pin defaults.
            if yes, !ignoreCommit, !noIgnoreCommit {
                initArgs.append("--no-ignore-commit")
            }
            if yes, !hooksPublish, !noHooksPublish {
                initArgs.append("--no-hooks-publish")
            }
            try CLISelfRunner.runOrThrow(initArgs, directory: directory)
        } else {
            print(ui.ok("\(ProjectConfigLoader.filename) already present"))
        }

        // 3. Protect
        CLIPrompt.step(current: 3, total: totalSteps, title: "Protect exposed paths")
        if skipProtect {
            print(ui.hint("Skipped (--skip-protect)"))
        } else {
            let shouldProtect: Bool
            if interactive {
                shouldProtect = CLIPrompt.yesNo(
                    question: "Hide required sensitive paths from AI tools?",
                    hint: includeRecommended
                        ? "Includes recommended exposures."
                        : "Required only; pass --include-recommended for SSH/AWS paths too.",
                    defaultYes: true
                )
            } else {
                shouldProtect = true
            }
            if shouldProtect {
                var protectArgs = ["protect", directory]
                if includeRecommended {
                    protectArgs.append("--include-recommended")
                }
                try CLISelfRunner.runOrThrow(protectArgs, directory: directory)
            } else {
                print(ui.hint("Skipped protect"))
            }
        }

        // 4. Hooks
        CLIPrompt.step(current: 4, total: totalSteps, title: "Install hooks")
        if skipHooks {
            print(ui.hint("Skipped (--skip-hooks)"))
        } else {
            let shouldHooks: Bool
            if interactive {
                shouldHooks = CLIPrompt.yesNo(
                    question: "Install git + AI-editor hooks?",
                    hint: "pre-commit check plus prompt/read/shell/MCP gates for detected editors.",
                    defaultYes: true
                )
            } else {
                shouldHooks = true
            }
            if shouldHooks {
                var hookArgs = ["hook", "install", "--path", directory]
                if yes || !interactive {
                    hookArgs.append("--yes")
                }
                try CLISelfRunner.runOrThrow(hookArgs, directory: directory)
            } else {
                print(ui.hint("Skipped hooks"))
            }
        }

        // 5. Show
        CLIPrompt.step(current: 5, total: totalSteps, title: "Verify")
        try CLISelfRunner.runOrThrow(["show", directory], directory: directory)

        print("")
        print(ui.ok("Setup complete"))
        print(ui.hint("Commit \(ProjectConfigLoader.filename) so the team shares the same rules."))
    }
}
