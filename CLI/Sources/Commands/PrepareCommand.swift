import ArgumentParser
import Foundation
import OffsendRuntime

struct Prepare: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create missing AI ignore files (.cursorignore, .claudeignore, …) for the project."
    )

    @Argument(help: "Directory to prepare. Defaults to the current directory.")
    var path: String?

    @Flag(name: .long, help: "Show which files would be created without writing them.")
    var dryRun = false

    @Flag(name: .long, help: "Also append missing sensitive-data patterns to existing ignore files.")
    var syncPatterns = false

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

        let report = CLISpinner(message: "Preparing...").runWhile {
            OffsendPrepareService(context: context).run(
                directoryURL: directoryURL,
                dryRun: dryRun,
                syncPatterns: syncPatterns
            )
        }

        let output = PrepareReporter().render(report, format: outputFormat)
        if !output.isEmpty {
            print(output)
        }

        if report.hasErrors {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}
