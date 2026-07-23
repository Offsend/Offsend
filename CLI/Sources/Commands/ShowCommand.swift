import ArgumentParser
import Foundation
import OffsendRuntime

struct Show: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List sensitive files exposed to AI tools (not covered by ignore files).",
        discussion: """
        Use --report to emit an anonymized, aggregated JSON report of AI context \
        hygiene instead (no paths or file names) — suitable for sharing or telemetry.
        Use --scan-history to content-scan local agent transcripts (same detectors as \
        `offsend history audit`). Or set context.history.scan_in_show: true in .offsend.yml.
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

    @Flag(
        name: .customLong("scan-history"),
        help: "Content-scan local agent transcripts for secret-shaped findings (slower)."
    )
    var scanHistory = false

    func validate() throws {
        if report {
            if let format, CLIParse.outputFormat(format) == .text {
                throw ValidationError("--report always emits JSON; --format text is not supported.")
            }
            if scanHistory {
                throw ValidationError("--scan-history is not supported with --report.")
            }
        } else if out != nil {
            throw ValidationError("--out requires --report.")
        }
    }

    mutating func run() async throws {
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
        let spinnerEnabled = outputFormat == .text && CLISpinner.shouldAnimate
        let spinnerMessage = scanHistory ? "Inspecting (scanning history)..." : "Inspecting..."
        let showReport = await CLISpinner(message: spinnerMessage, enabled: spinnerEnabled).runWhile {
            await OffsendShowService(context: context).runAsync(
                directoryURL: directoryURL,
                scanHistory: scanHistory
            )
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
