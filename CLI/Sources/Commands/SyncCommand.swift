import ArgumentParser
import Foundation
import OffsendRuntime

struct Sync: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Materialize ignore.patterns from .offsend.yml into AI ignore files.",
        discussion: """
        Writes the managed offsend block into every known AI ignore file \
        (.cursorignore, .claudeignore, …). When ignore.commit is false (default), \
        also updates .git/info/exclude so those files stay out of the repository. \
        User-authored lines outside the managed block are preserved.
        """
    )

    @Option(name: .long, help: "Project directory. Defaults to the current directory.")
    var path: String?

    @Flag(name: .long, help: "Show what would change without writing files.")
    var dryRun = false

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

        let report = OffsendIgnoreSyncService(context: context).run(
            directoryURL: directoryURL,
            dryRun: dryRun
        )
        let output = IgnoreSyncReporter().render(report, format: outputFormat)
        if !output.isEmpty {
            print(output)
        }
        if report.hasErrors {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}
