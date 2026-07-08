import ArgumentParser
import Foundation
import OffsendRuntime

/// Starter contents written by `offsend init`. Kept in sync with `.offsend.yml.example`.
private let projectConfigTemplate = """
version: 1

check:
  fail_on: block
  policy: false
  exclude:
    - "*.lock"
    - "vendor/**"
    - "DerivedData/**"
  detectors:
    # All detector IDs you can list under `disable:`:
    #   email, phone, money, url, ipAddress, internalDomain, contractId,
    #   invoiceId, orderId, apiKeyGeneric, openAIAPIKey, awsAccessKeyId,
    #   githubToken, slackToken, stripeKey, jwt, privateKey, sshPrivateKey,
    #   databaseURLWithPassword, bearerToken, highEntropyString, creditCardLike,
    #   iban, customClient, customCompany, customProject, customSensitiveTerm,
    #   customInternalDomain, personName, streetAddress, governmentId
    # Default keeps only secret/credential detectors active.
    disable:
      - email
      - phone
      - money
      - url
      - ipAddress
      - internalDomain
      - contractId
      - invoiceId
      - orderId
      - creditCardLike
      - iban
      - personName
      - streetAddress
      - governmentId
  # Custom dictionaries are matched in addition to the built-in detectors.
  # kind: client | company | project | sensitiveTerm | internalDomain | regex
  # For every kind except `regex`, `value` is matched literally (with word boundaries).
  # For `regex`, `value` is used as a regular expression pattern verbatim.
  dictionaries: []

hooks:
  type: pre-commit
  fail_on: block
  policy: false

"""

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a starter \(ProjectConfigLoader.filename) configuration file."
    )

    @Option(name: .long, help: "Directory to initialize. Defaults to the current directory.")
    var path: String?

    @Flag(name: .long, help: "Overwrite an existing \(ProjectConfigLoader.filename).")
    var force = false

    mutating func run() throws {
        let configURL = Self.configURL(forDirectory: path)

        if FileManager.default.fileExists(atPath: configURL.path), !force {
            CLIError.exit(
                .error,
                message: "\(ProjectConfigLoader.filename) already exists at \(configURL.path). Use --force to overwrite."
            )
        }

        do {
            try projectConfigTemplate.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            CLIError.exit(.error, message: "Failed to write \(configURL.path): \(error.localizedDescription)")
        }

        print("Created \(configURL.path)")
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
