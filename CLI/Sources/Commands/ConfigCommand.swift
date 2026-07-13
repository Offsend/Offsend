import ArgumentParser
import Foundation
import OffsendRuntime

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a starter \(ProjectConfigLoader.filename) configuration file."
    )

    @Option(name: .long, help: "Directory to initialize. Defaults to the current directory.")
    var path: String?

    @Option(
        name: .long,
        parsing: .singleValue,
        help: """
        Exclude preset to expand into check.exclude. Repeatable, or comma-separated \
        (e.g. --template node --template swift, or --template js,python). \
        Case-insensitive; aliases: js/ts→node, ios→swift. Always includes 'common'. \
        Use --list-templates to print all presets.
        """
    )
    var template: [String] = []

    @Flag(name: .long, help: "Overwrite an existing \(ProjectConfigLoader.filename).")
    var force = false

    @Flag(
        name: .long,
        help: "Merge template exclude patterns into an existing \(ProjectConfigLoader.filename) instead of overwriting."
    )
    var mergeExclude = false

    @Flag(name: .long, help: "Print available exclude templates and exit.")
    var listTemplates = false

    mutating func run() throws {
        if listTemplates {
            print(ProjectConfigTemplates.listTemplatesText())
            return
        }

        if force, mergeExclude {
            CLIError.exit(.error, message: "Use either --force or --merge-exclude, not both.")
        }

        let configURL = Self.configURL(forDirectory: path)
        let exists = FileManager.default.fileExists(atPath: configURL.path)

        let templates: [ProjectConfigTemplateID]
        do {
            templates = try ProjectConfigTemplates.resolve(rawValues: template)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }

        let labels = templates.map(\.rawValue).joined(separator: ", ")
        let templatePatterns = ProjectConfigTemplates.excludePatterns(for: templates)

        if mergeExclude {
            guard exists else {
                CLIError.exit(
                    .error,
                    message: "No \(ProjectConfigLoader.filename) at \(configURL.path). Run `offsend init` first, or omit --merge-exclude."
                )
            }

            let existing: String
            do {
                existing = try String(contentsOf: configURL, encoding: .utf8)
            } catch {
                CLIError.exit(.error, message: "Failed to read \(configURL.path): \(error.localizedDescription)")
            }

            let merged: (yaml: String, added: [String])
            do {
                merged = try ProjectConfigTemplates.mergingExclude(intoYAML: existing, patterns: templatePatterns)
            } catch {
                CLIError.exit(.error, message: "Failed to merge exclude patterns: \(error.localizedDescription)")
            }

            do {
                try merged.yaml.write(to: configURL, atomically: true, encoding: .utf8)
            } catch {
                CLIError.exit(.error, message: "Failed to write \(configURL.path): \(error.localizedDescription)")
            }

            if merged.added.isEmpty {
                print("No new exclude patterns to add in \(configURL.path) (templates: \(labels))")
            } else {
                print("Updated \(configURL.path) — added \(merged.added.count) exclude pattern(s) (templates: \(labels))")
            }
            printNextSteps()
            return
        }

        if exists, !force {
            CLIError.exit(
                .error,
                message: "\(ProjectConfigLoader.filename) already exists at \(configURL.path). Use --force to overwrite or --merge-exclude to add patterns."
            )
        }

        let contents = ProjectConfigTemplates.renderYAML(templates: templates)

        do {
            try contents.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            CLIError.exit(.error, message: "Failed to write \(configURL.path): \(error.localizedDescription)")
        }

        print("Created \(configURL.path) (templates: \(labels))")
        printNextSteps()
    }

    private func printNextSteps() {
        print("Commit \(ProjectConfigLoader.filename) so hooks and CI share the same rules.")
        print("Next: offsend check . --quiet")
    }

    /// Resolves the config path at the git repository root, falling back to the
    /// given directory when not inside a repository. Mirrors ProjectConfigLoader.
    static func configURL(forDirectory path: String?) -> URL {
        let directory = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL
        let root = (try? GitRepositoryResolver().repositoryRoot(startingAt: directory)) ?? directory
        return root.appendingPathComponent(ProjectConfigLoader.filename)
    }
}

struct Edit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Open \(ProjectConfigLoader.filename) in your editor."
    )

    @Option(name: .long, help: "Directory to look in. Defaults to the current directory.")
    var path: String?

    mutating func run() throws {
        let configURL = Init.configURL(forDirectory: path)

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            CLIError.exit(
                .error,
                message: "No \(ProjectConfigLoader.filename) found at \(configURL.path). Run `offsend init` first."
            )
        }

        let environment = ProcessInfo.processInfo.environment
        let editor = environment["VISUAL"] ?? environment["EDITOR"]

        let process = Process()
        if let editor, !editor.trimmingCharacters(in: .whitespaces).isEmpty {
            // $EDITOR may contain arguments (e.g. "code --wait"); run it via the shell.
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "\(editor) \"$1\"", "sh", configURL.path]
        } else {
            #if os(macOS)
            // Fall back to the default GUI text editor.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-t", configURL.path]
            #else
            CLIError.exit(
                .error,
                message: "Set $EDITOR or $VISUAL to edit \(ProjectConfigLoader.filename)."
            )
            #endif
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            CLIError.exit(.error, message: "Failed to open editor: \(error.localizedDescription)")
        }

        if process.terminationStatus != 0 {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}
