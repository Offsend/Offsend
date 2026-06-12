import ArgumentParser
import Foundation
import OffsendRuntime

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Verify local Offsend CLI setup and dependencies."
    )

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    mutating func run() throws {
        let outputFormat = CLIParse.outputFormat(format)
        let report = OffsendDoctor().run()
        print(DoctorReporter().render(report, format: outputFormat))

        if !report.isHealthy {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}
