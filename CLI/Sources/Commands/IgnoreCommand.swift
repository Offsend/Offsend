import ArgumentParser
import Foundation
import OffsendRuntime

struct Ignore: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add paths or patterns to every AI ignore file (.cursorignore, .claudeignore, …).",
        discussion: """
        Appends each pattern to all AI ignore files that already exist in the project. \
        If the project has none yet, the standard set is created first (same files as \
        `offsend prepare`). `.gitignore` is never modified.

        Patterns are gitignore-style: existing directories gain a trailing slash, \
        absolute paths under the project root become relative, globs pass through as-is.

        Note: this manages editor ignore files. Scanner exclusions live in .offsend.yml \
        under check.exclude.
        """
    )

    @Argument(help: "Paths or glob patterns to ignore (e.g. secrets/, *.pem, config/prod.json).")
    var patterns: [String]

    @Option(name: .long, help: "Project directory. Defaults to the current directory.")
    var path: String?

    @Flag(name: .long, help: "Show which files would change without writing them.")
    var dryRun = false

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    func validate() throws {
        guard !patterns.isEmpty else {
            throw ValidationError("Provide at least one path or pattern to ignore.")
        }
    }

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

        let report = OffsendIgnoreService(context: context).run(
            directoryURL: directoryURL,
            patterns: patterns,
            dryRun: dryRun
        )

        let output = IgnoreReporter().render(report, format: outputFormat)
        if !output.isEmpty {
            print(output)
        }

        if report.hasErrors {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}
