import ArgumentParser
import Foundation
import OffsendRuntime

struct Ignore: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add paths or patterns to team ignore policy (.offsend.yml) or locally.",
        discussion: """
        By default, patterns are added to ignore.patterns in .offsend.yml and then \
        materialized into AI ignore files (published to the team when you \
        commit .offsend.yml).

        Use --local to append patterns only to AI ignore files on this machine. \
        Local rules are not written to .offsend.yml and will not be shared.

        Use --merge-defaults after upgrading Offsend to merge the current built-in \
        AI privacy patterns into ignore.patterns (then commit .offsend.yml).

        To re-materialize ignore.patterns after editing .offsend.yml by hand, \
        run `offsend sync` (or `offsend sync --no-hooks` for ignore files only).

        Scanner exclusions remain under check.exclude in .offsend.yml.
        """
    )

    @Argument(help: "Paths or glob patterns to ignore (e.g. secrets/, *.pem, config/prod.json).")
    var patterns: [String] = []

    @Flag(
        name: .long,
        help: "Add patterns only to local AI ignore files; do not update .offsend.yml."
    )
    var local = false

    @Flag(
        name: .customLong("merge-defaults"),
        help: """
        Merge the current built-in AI privacy default patterns into ignore.patterns \
        (upgrade path for existing .offsend.yml), then materialize ignore files. \
        Do not pass pattern arguments with this flag.
        """
    )
    var mergeDefaults = false

    @Option(name: .long, help: "Project directory. Defaults to the current directory.")
    var path: String?

    @Flag(name: .long, help: "Show which files would change without writing them.")
    var dryRun = false

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    func validate() throws {
        if mergeDefaults {
            if local {
                throw ValidationError("--merge-defaults cannot be used with --local.")
            }
            if !patterns.isEmpty {
                throw ValidationError("Do not pass patterns with --merge-defaults.")
            }
            return
        }
        guard !patterns.isEmpty else {
            throw ValidationError(
                "Provide at least one path or pattern to ignore, or use --merge-defaults. "
                    + "To re-materialize .offsend.yml, run `offsend sync`."
            )
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

        if local {
            let report = OffsendIgnoreService(context: context).run(
                directoryURL: directoryURL,
                patterns: patterns,
                dryRun: dryRun
            )
            let useColor = CLIColor.enabled(for: outputFormat)
            let output = IgnoreReporter().render(report, format: outputFormat, scope: .local, useColor: useColor)
            if !output.isEmpty {
                print(output)
            }
            if report.hasErrors {
                throw ExitCode(OffsendExitCode.error.rawValue)
            }
            return
        }

        let patternsToPromote = mergeDefaults
            ? OffsendIgnoreSyncService.builtInPrivacyPatterns
            : patterns

        let result = OffsendIgnoreSyncService(context: context).promotePatterns(
            patternsToPromote,
            directoryURL: directoryURL,
            dryRun: dryRun
        )

        if outputFormat == .json {
            struct Payload: Encodable {
                let scope: String
                let published: Bool
                let addedToConfig: [String]
                let configPath: String?
                let dryRun: Bool
                let sync: IgnoreSyncJSON
            }
            struct IgnoreSyncJSON: Encodable {
                let patterns: [String]
                let createdRelativePaths: [String]
                let updatedRelativePaths: [String]
                let unchangedRelativePaths: [String]
                let gitignoreUpdated: Bool
                let excludeUpdated: Bool
                let errors: [String]
            }
            let payload = Payload(
                scope: "project",
                published: true,
                addedToConfig: result.added,
                configPath: result.configPath,
                dryRun: dryRun,
                sync: IgnoreSyncJSON(
                    patterns: result.sync.patterns,
                    createdRelativePaths: result.sync.createdRelativePaths,
                    updatedRelativePaths: result.sync.updatedRelativePaths,
                    unchangedRelativePaths: result.sync.unchangedRelativePaths,
                    gitignoreUpdated: result.sync.gitignoreUpdated,
                    excludeUpdated: result.sync.excludeUpdated,
                    errors: result.sync.errors
                )
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(payload), let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } else {
            let useColor = CLIColor.enabled(for: .text)
            let ui = CLIText(useColor: useColor)
            if let configPath = result.configPath {
                if result.added.isEmpty {
                    let note = mergeDefaults
                        ? "Built-in defaults already present in \(configPath)"
                        : "No new patterns for \(configPath) (already present or unchanged)"
                    print(ui.ok(note))
                } else if dryRun {
                    print(ui.section("Config"))
                    let hint = mergeDefaults
                        ? "Would merge built-in defaults into \(ProjectConfigLoader.filename):"
                        : "Would add to \(ProjectConfigLoader.filename):"
                    print(ui.hint(hint))
                    for pattern in result.added {
                        print(ui.add(pattern))
                    }
                } else {
                    print(ui.section("Config"))
                    let hint = mergeDefaults
                        ? "Merged built-in defaults into \(ProjectConfigLoader.filename):"
                        : "Added to \(ProjectConfigLoader.filename):"
                    print(ui.hint(hint))
                    for pattern in result.added {
                        print(ui.add(pattern))
                    }
                }
            }
            let syncText = IgnoreSyncReporter().render(result.sync, format: .text, useColor: useColor)
            if !syncText.isEmpty {
                print(syncText)
            }
        }

        if result.sync.hasErrors {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}
