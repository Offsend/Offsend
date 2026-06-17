import ArgumentParser
import Foundation

@main
struct OffsendCLI: AsyncParsableCommand {
    // Bundle.main reads the Info.plist embedded into the binary
    // (CREATE_INFOPLIST_SECTION_IN_BINARY) regardless of how the executable
    // was invoked, unlike argv[0] which may be a bare name from PATH lookup.
    private static let marketingVersion: String = {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }
        return "0.0.0"
    }()

    static let configuration = CommandConfiguration(
        commandName: "offsend",
        abstract: "Local sensitive data checks for developers.",
        version: marketingVersion,
        subcommands: [Init.self, Edit.self, Check.self, Show.self, Prepare.self, Hook.self, Doctor.self],
        defaultSubcommand: nil
    )
}
