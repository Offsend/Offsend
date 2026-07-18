import ArgumentParser
import Foundation
import OffsendRuntime

struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the sensitive files that would be sent to AI tools (not covered by ignore files).",
        discussion: """
        Use --report to emit an anonymized, aggregated JSON report of AI context \
        hygiene instead (no paths or file names) — suitable for sharing or telemetry.
        """
    )

    @Argument(help: "Directory to inspect. Defaults to the current directory.")
    var path: String?

    @Option(name: .long, help: "Output format (text, json).")
    var format: String?

    @Flag(name: .long, help: "Emit an anonymized aggregated JSON report (no paths or file names).")
    var report = false

    @Option(name: .long, help: "With --report: write the JSON report to this file instead of stdout.")
    var out: String?

    func validate() throws {
        if report {
            if let format, CLIParse.outputFormat(format) == .text {
                throw ValidationError("--report always emits JSON; --format text is not supported.")
            }
        } else if out != nil {
            throw ValidationError("--out requires --report.")
        }
    }

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

        if report {
            try runReport(context: context, directoryURL: directoryURL)
            return
        }

        let outputFormat = CLIParse.outputFormat(format ?? CheckOutputFormat.text.rawValue)
        let showReport = CLISpinner(message: "Inspecting...").runWhile {
            OffsendShowService(context: context).run(directoryURL: directoryURL)
        }

        let useColor = CLIColor.enabled(for: outputFormat)
        let output = ShowReporter().render(showReport, format: outputFormat, useColor: useColor)
        if !output.isEmpty {
            print(output)
        }

        if showReport.hasErrors {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }

    private func runReport(context: OffsendRuntimeContext, directoryURL: URL) throws {
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
