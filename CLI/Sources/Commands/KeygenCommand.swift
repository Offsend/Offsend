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

    @Flag(name: .long, help: "Write 32 raw bytes (requires --output). Default is base64 text.")
    var raw = false

    @Option(name: .long, help: "Working directory used for relative --output paths.")
    var workingDirectory: String?

    mutating func run() throws {
        if raw, output == nil {
            CLIError.exit(.error, message: "--raw requires --output (refusing to write binary key to a terminal).")
        }

        let keyData = SealKeyResolver.generate()
        let workingURL = URL(
            fileURLWithPath: workingDirectory ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        if let output {
            let url = URL(fileURLWithPath: output, relativeTo: workingURL).standardizedFileURL
            let payload: Data
            if raw {
                payload = keyData
            } else {
                payload = Data((keyData.base64EncodedString() + "\n").utf8)
            }
            do {
                try payload.write(to: url, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: url.path
                )
            } catch {
                CLIError.exit(.error, message: "Failed to write key to \(url.path): \(error.localizedDescription)")
            }
            fputs("Wrote seal key to \(url.path)\n", stderr)
            return
        }

        print(keyData.base64EncodedString())
    }
}
