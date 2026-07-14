import ArgumentParser
import Foundation
import MaskingCore
import OffsendRuntime
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct Unseal: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Restore plaintext from {{TYPE:v1.…}} seal tokens."
    )

    @Argument(help: "Text file to unseal. Omit to read from stdin.")
    var path: String?

    @Option(name: .long, help: "Path to a seal key file (32 raw bytes or base64).")
    var keyFile: String?

    @Option(name: .long, help: "Named seal key in ~/.offsend/keys/NAME.key.")
    var keyName: String?

    @Option(name: [.short, .long], help: "Write output to this file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Atomically replace an existing output file.")
    var force = false

    @Option(name: .long, help: "Working directory used for relative paths.")
    var workingDirectory: String?

    mutating func run() throws {
        let workingURL = URL(
            fileURLWithPath: workingDirectory ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL
        if force, output == nil {
            CLIError.exit(.error, message: "--force requires --output.")
        }
        let keyData = CLIParse.sealKey(
            keyFile: keyFile,
            keyName: keyName,
            workingDirectory: workingURL
        )

        let text = SealIO.readInput(path: path, workingDirectory: workingURL)
        let context: OffsendRuntimeContext
        do {
            context = try OffsendRuntimeContext.load()
        } catch {
            CLIError.exit(.error, message: "Failed to load Offsend settings: \(error.localizedDescription)")
        }

        let restored: String
        do {
            restored = try OffsendSealService(context: context).unseal(text: text, keyData: keyData)
        } catch let error as SealError {
            CLIError.exit(.error, message: error.localizedDescription)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }

        SealIO.writeOutput(
            restored,
            to: output,
            workingDirectory: workingURL,
            force: force
        )
    }
}
