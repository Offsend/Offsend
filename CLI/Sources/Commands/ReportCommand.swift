import ArgumentParser
import Foundation
import OffsendRuntime

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Emit an anonymized, aggregated JSON report of AI context hygiene (no paths or file names)."
    )

    @Argument(help: "Directory to inspect. Defaults to the current directory.")
    var path: String?

    @Option(name: .long, help: "Write the JSON report to this file instead of stdout.")
    var out: String?

    mutating func run() throws {
        let context: OffsendRuntimeContext
        do {
            context = try OffsendRuntimeContext.load()
        } catch {
            CLIError.exit(.error, message: "Failed to load Offsend settings: \(error.localizedDescription)")
        }

        let directoryURL = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        let report = CLISpinner(message: "Inspecting...").runWhile {
            OffsendReportService(context: context).run(directoryURL: directoryURL)
        }

        let output = ReportReporter().renderJSON(
            report,
            toolVersion: CLIVersion.marketing,
            generatedAt: Date()
        )

        if let out {
            let outURL = URL(
                fileURLWithPath: out,
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
            do {
                try (output + "\n").write(to: outURL, atomically: true, encoding: .utf8)
            } catch {
                CLIError.exit(.error, message: "Failed to write report to \(outURL.path): \(error.localizedDescription)")
            }
        } else {
            print(output)
        }

        if report.hasErrors {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}
