import ArgumentParser
import Foundation
import OffsendRuntime

struct Protect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "protect",
        abstract: "Hide exposed sensitive paths from AI tools (create ignore files + add required patterns).",
        discussion: """
        Runs the same path audit as `offsend show`, creates missing AI ignore files \
        (like `offsend prepare`), then appends canonical ignore lines for every \
        required exposed pattern (like `offsend ignore`). Use --include-recommended \
        to also cover recommended exposures. Preview with --dry-run, then verify with \
        `offsend show`. When `.offsend.yml` has `context.history.scrub_on_protect: true`, \
        also dry-runs (or applies, unless --dry-run) a local agent-history scrub.
        """
    )

    @Argument(help: "Directory to protect. Defaults to the current directory.")
    var path: String?

    @Flag(name: .long, help: "Show what would change without writing ignore files.")
    var dryRun = false

    @Flag(
        name: .long,
        help: "Also ignore recommended exposures (SSH, AWS paths, …), not only required."
    )
    var includeRecommended = false

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    mutating func run() async throws {
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

        let report = CLISpinner(message: "Protecting...").runWhile {
            OffsendProtectService(context: context).run(
                directoryURL: directoryURL,
                dryRun: dryRun,
                includeRecommended: includeRecommended
            )
        }

        let output = ProtectReporter().render(report, format: outputFormat)
        if !output.isEmpty {
            print(output)
        }

        let projectConfig = CLIParse.projectConfig(from: directoryURL)
        if projectConfig?.context?.history?.scrubOnProtect == true {
            let home: URL = {
                if let value = ProcessInfo.processInfo.environment["HOME"], !value.isEmpty {
                    return URL(fileURLWithPath: value)
                }
                return FileManager.default.homeDirectoryForCurrentUser
            }()
            let resolved = OptionsResolver.resolveCheckOptions(
                overrides: CLICheckOverrides(),
                projectConfig: projectConfig,
                staged: false
            )
            let scrub = await OffsendHistoryService().scrub(
                projectRoot: directoryURL,
                homeDirectory: home,
                context: context,
                apply: !dryRun,
                allProjects: false,
                disabledDetectors: resolved.disabledDetectors,
                customDictionaries: resolved.customDictionaries
            )
            let scrubOut = OffsendHistoryReporter.renderScrub(scrub, format: outputFormat)
            if !scrubOut.isEmpty {
                print(scrubOut)
            }
        }

        if report.hasErrors {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}
