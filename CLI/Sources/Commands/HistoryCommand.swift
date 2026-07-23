import ArgumentParser
import Foundation
import OffsendRuntime

struct History: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Audit or scrub secret-shaped values in local AI agent transcripts.",
        subcommands: [HistoryAudit.self, HistoryScrub.self]
    )
}

struct HistoryAudit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Scan local Cursor/Claude agent transcripts for secret-shaped values."
    )

    @Option(name: .long, help: "Project directory used to scope Cursor project transcripts. Defaults to cwd.")
    var path: String?

    @Flag(name: .long, help: "Scan transcripts for every project under ~/.cursor and ~/.claude.")
    var all = false

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    mutating func run() async throws {
        let outputFormat = CLIParse.outputFormat(format)
        let context: OffsendRuntimeContext
        do {
            context = try OffsendRuntimeContext.load()
        } catch {
            CLIError.exit(.error, message: "Failed to load Offsend settings: \(error.localizedDescription)")
        }

        let projectRoot = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL
        let home = defaultHistoryHomeDirectory()
        let projectConfig = CLIParse.projectConfig(from: projectRoot)
        let resolved = OptionsResolver.resolveCheckOptions(
            overrides: CLICheckOverrides(),
            projectConfig: projectConfig,
            staged: false
        )

        let spinnerEnabled = outputFormat == .text && CLISpinner.shouldAnimate
        let report = await CLISpinner(message: "Auditing agent history...", enabled: spinnerEnabled).runWhile {
            await OffsendHistoryService().audit(
                projectRoot: projectRoot,
                homeDirectory: home,
                context: context,
                allProjects: all,
                disabledDetectors: resolved.disabledDetectors,
                customDictionaries: resolved.customDictionaries
            )
        }

        let useColor = CLIColor.enabled(for: outputFormat)
        let output = OffsendHistoryReporter.renderAudit(report, format: outputFormat, useColor: useColor)
        if !output.isEmpty {
            print(output)
        }
        if !report.errors.isEmpty {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
        if report.hasFindings {
            throw ExitCode(OffsendExitCode.findings.rawValue)
        }
    }
}

struct HistoryScrub: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scrub",
        abstract: "Redact secret-shaped values in local agent transcripts (dry-run unless --apply)."
    )

    @Option(name: .long, help: "Project directory used to scope Cursor project transcripts. Defaults to cwd.")
    var path: String?

    @Flag(name: .long, help: "Scan/scrub transcripts for every project under ~/.cursor and ~/.claude.")
    var all = false

    @Flag(name: .long, help: "Write redactions to disk. Without this flag, only report what would change.")
    var apply = false

    @Option(name: .long, help: "Output format (text, json).")
    var format: String = CheckOutputFormat.text.rawValue

    mutating func run() async throws {
        let outputFormat = CLIParse.outputFormat(format)
        let context: OffsendRuntimeContext
        do {
            context = try OffsendRuntimeContext.load()
        } catch {
            CLIError.exit(.error, message: "Failed to load Offsend settings: \(error.localizedDescription)")
        }

        let projectRoot = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL
        let home = defaultHistoryHomeDirectory()
        let projectConfig = CLIParse.projectConfig(from: projectRoot)
        let resolved = OptionsResolver.resolveCheckOptions(
            overrides: CLICheckOverrides(),
            projectConfig: projectConfig,
            staged: false
        )

        let spinnerEnabled = outputFormat == .text && CLISpinner.shouldAnimate
        let report = await CLISpinner(
            message: apply ? "Scrubbing..." : "Dry-run scrub...",
            enabled: spinnerEnabled
        ).runWhile {
            await OffsendHistoryService().scrub(
                projectRoot: projectRoot,
                homeDirectory: home,
                context: context,
                apply: apply,
                allProjects: all,
                disabledDetectors: resolved.disabledDetectors,
                customDictionaries: resolved.customDictionaries
            )
        }

        let useColor = CLIColor.enabled(for: outputFormat)
        let output = OffsendHistoryReporter.renderScrub(report, format: outputFormat, useColor: useColor)
        if !output.isEmpty {
            print(output)
        }
        if !report.errors.isEmpty {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}

private func defaultHistoryHomeDirectory() -> URL {
    if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
        return URL(fileURLWithPath: home)
    }
    return FileManager.default.homeDirectoryForCurrentUser
}
