import ArgumentParser
import Foundation
import OffsendRuntime

struct Policy: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage the user-approved runtime policy used by editor gates.",
        subcommands: [PolicyTrust.self, PolicyStatus.self, PolicyForget.self]
    )
}

struct PolicyTrust: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trust",
        abstract: "Explicitly trust the current repository policy for editor gates."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    mutating func run() throws {
        guard CLIPrompt.isInteractiveTTY else {
            CLIError.exit(
                .error,
                message: "`offsend policy trust` requires an interactive terminal. "
                    + "Run it yourself after reviewing \(ProjectConfigLoader.filename); "
                    + "it cannot be approved non-interactively."
            )
        }
        let directory = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL
        _ = try ProjectConfigLoader().load(from: directory)
        let configURL = ProjectConfigLoader().configURL(for: directory)
        guard let configURL else {
            CLIError.exit(
                .error,
                message: "No \(ProjectConfigLoader.filename) found. Run `offsend init` first."
            )
        }
        let approved = CLIPrompt.yesNo(
            question: "Trust the current \(ProjectConfigLoader.filename) for editor gates?",
            hint: "Review \(configURL.path) first. Later changes will block gates until you trust again.",
            defaultYes: false
        )
        guard approved else {
            print("Policy was not trusted.")
            return
        }

        do {
            let snapshot = try OffsendPolicySnapshotStore().trust(directory: directory)
            let ui = CLIText(useColor: CLIColor.enabled(for: .text))
            print(ui.ok("Trusted editor-gate policy"))
            print(ui.hint("  repository: \(snapshot.repositoryPath)"))
            print(ui.hint("  hash: \(snapshot.configHash.prefix(12))…"))
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }
    }
}

struct PolicyStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show whether the repository policy matches the trusted snapshot."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    mutating func run() throws {
        let directory = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL
        switch OffsendPolicySnapshotStore().status(directory: directory) {
        case .missing:
            print("Policy snapshot: missing")
            print("Run `offsend policy trust` in an interactive terminal after reviewing .offsend.yml.")
        case .trusted(let snapshot):
            print("Policy snapshot: trusted")
            print("Hash: \(snapshot.configHash.prefix(12))…")
        case .drift(_, let reason):
            print("Policy snapshot: drift")
            print("Reason: \(reason)")
            throw ExitCode(OffsendExitCode.findings.rawValue)
        case .invalidSnapshot(let reason):
            print("Policy snapshot: invalid")
            print("Reason: \(reason)")
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
    }
}

struct PolicyForget: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forget",
        abstract: "Remove the local trusted policy snapshot."
    )

    @Option(name: .long, help: "Repository path. Defaults to the current directory.")
    var path: String?

    mutating func run() throws {
        guard CLIPrompt.isInteractiveTTY else {
            CLIError.exit(.error, message: "`offsend policy forget` requires an interactive terminal.")
        }
        let directory = URL(
            fileURLWithPath: path ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL
        let approved = CLIPrompt.yesNo(
            question: "Remove the trusted policy snapshot?",
            hint: "Until the policy is trusted again, gates ignore any field that would loosen them below its built-in default.",
            defaultYes: false
        )
        guard approved else { return }
        do {
            try OffsendPolicySnapshotStore().remove(directory: directory)
            print("Removed trusted policy snapshot.")
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }
    }
}
