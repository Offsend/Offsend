import ArgumentParser
import Foundation
import OffsendRuntime

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Verify local Offsend CLI setup and dependencies."
    )

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    @Flag(
        name: .customLong("no-follow"),
        help: "Skip interactive “run next step?” prompt (default outside TTY)."
    )
    var noFollow = false

    mutating func run() async throws {
        let outputFormat = CLIParse.outputFormat(format)
        let useColor = CLIColor.enabled(for: outputFormat)
        let report = await OffsendDoctor().run()
        print(DoctorReporter().render(report, format: outputFormat, useColor: useColor))

        if !report.isHealthy {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }

        try offerNextAction(report: report, outputFormat: outputFormat)
    }

    private func offerNextAction(report: DoctorReport, outputFormat: CheckOutputFormat) throws {
        guard outputFormat == .text else { return }
        guard !noFollow else { return }
        guard CLIPrompt.isInteractiveTTY else { return }
        guard let action = report.suggestedActions.first else { return }
        let command = DoctorReport.command(from: action)
        guard command.hasPrefix("offsend ") else { return }

        let ui = CLIText(useColor: CLIColor.enabled(for: .text))
        print("")
        print(ui.section("Follow-up"))
        print(ui.hint(action))

        guard CLIPrompt.yesNo(
            question: "Run this step now?",
            hint: command,
            defaultYes: true
        ) else {
            return
        }

        let args = Array(command.split(separator: " ").dropFirst().map(String.init))
        // Refuse placeholders like --template <stack>
        if args.contains(where: { $0.contains("<") || $0.contains(">") }) {
            print(ui.warn("Command needs your input — run it manually: \(command)"))
            return
        }
        try CLISelfRunner.runOrThrow(args)
    }
}
