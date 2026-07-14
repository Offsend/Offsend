import ArgumentParser
import Foundation
import OffsendRuntime
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct Keygen: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keygen",
        abstract: "Generate a 32-byte seal key for use with seal / unseal."
    )

    @Option(name: [.short, .long], help: "Write the key to this file instead of stdout.")
    var output: String?

    @Flag(name: .customLong("default"), help: "Write the key to ~/.offsend/seal.key (refuses overwrite unless --force).")
    var installDefault = false

    @Option(name: .long, help: "Write a named key to ~/.offsend/keys/NAME.key (refuses overwrite unless --force).")
    var name: String?

    @Flag(
        name: .long,
        help: "Overwrite an existing key file at the target path (destructive; previous key is lost)."
    )
    var force = false

    @Flag(name: .long, help: "Write 32 raw bytes (requires a file target). Default is base64 text.")
    var raw = false

    @Option(name: .long, help: "Working directory used for relative --output paths.")
    var workingDirectory: String?

    mutating func run() throws {
        let keyData = SealKeyResolver.generate()
        let workingURL = URL(
            fileURLWithPath: workingDirectory ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        let targetURL: URL?
        do {
            targetURL = try resolveTargetURL(workingDirectory: workingURL)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }

        guard let targetURL else {
            if raw {
                CLIError.exit(.error, message: "--raw requires a file target (--output, --default, or --name).")
            }
            print(keyData.base64EncodedString())
            return
        }

        do {
            try SealKeyPaths.writeKey(keyData, to: targetURL, raw: raw, force: force)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }
        fputs("Wrote seal key to \(targetURL.path)\n", stderr)
    }

    private func resolveTargetURL(workingDirectory: URL) throws -> URL? {
        let targetFlags = [output != nil, installDefault, name != nil].filter { $0 }.count
        if targetFlags > 1 {
            CLIError.exit(
                .error,
                message: "Use only one target: --output, --default, or --name."
            )
        }

        if let output {
            return URL(fileURLWithPath: output, relativeTo: workingDirectory).standardizedFileURL
        }
        if installDefault {
            return SealKeyPaths.defaultKeyURL()
        }
        if let name {
            return try SealKeyPaths.namedKeyURL(name: name)
        }
        return nil
    }
}
