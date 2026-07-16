import ArgumentParser
import Foundation
import OffsendRuntime

struct Protect: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "protect",
        abstract: "Hide exposed sensitive paths from AI tools (create ignore files + add required patterns).",
        discussion: """
        Runs the same path audit as `offsend show`, creates missing AI ignore files \
        (like `offsend prepare`), then appends canonical ignore lines for every \
        required exposed pattern (like `offsend ignore`). Use --include-recommended \
        to also cover recommended exposures. Preview with --dry-run, then verify with \
        `offsend show`.
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

        if report.hasErrors {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}
