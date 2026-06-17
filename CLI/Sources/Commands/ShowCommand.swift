import ArgumentParser
import Foundation
import OffsendRuntime

struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the sensitive files that would be sent to AI tools (not covered by ignore files)."
    )

    @Argument(help: "Directory to inspect. Defaults to the current directory.")
    var path: String?

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

        let report = OffsendShowService(context: context).run(directoryURL: directoryURL)

        let output = ShowReporter().render(report, format: outputFormat)
        if !output.isEmpty {
            print(output)
        }

        if report.hasErrors {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}
