import ArgumentParser
import Foundation

@main
struct OffsendCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "offsend",
        abstract: "Local sensitive data checks for developers.",
        version: CLIVersion.marketing,
        subcommands: [Init.self, Edit.self, Check.self, Show.self, Report.self, Prepare.self, Hook.self, Doctor.self],
        defaultSubcommand: nil
    )
}
