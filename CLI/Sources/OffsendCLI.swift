import ArgumentParser
import Foundation

@main
struct OffsendCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "offsend",
        abstract: "Local sensitive data checks for developers.",
        version: CLIVersion.marketing,
        subcommands: [
            Setup.self,
            Init.self,
            Edit.self,
            Protect.self,
            Show.self,
            Ignore.self,
            Check.self,
            Hook.self,
            History.self,
            Seal.self,
            Unseal.self,
            Keygen.self,
            Doctor.self,
        ],
        defaultSubcommand: nil
    )
}
