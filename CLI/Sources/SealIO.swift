import Foundation
import OffsendRuntime

enum SealIO {
    static func readInput(path: String?, workingDirectory: URL) -> String {
        if let path {
            let url = URL(fileURLWithPath: path, relativeTo: workingDirectory).standardizedFileURL
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                CLIError.exit(.error, message: "Failed to read \(url.path): \(error.localizedDescription)")
            }
        }

        do {
            return try CLIStdin.readUTF8()
        } catch let error as CLIStdin.ReadError {
            if case .tty = error {
                CLIError.exit(.error, message: "Provide a file path or pipe text on stdin.")
            }
            CLIError.exit(.error, message: error.message)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }
    }

    static func writeOutput(_ text: String, to outputPath: String?, workingDirectory: URL) {
        if let outputPath {
            let url = URL(fileURLWithPath: outputPath, relativeTo: workingDirectory).standardizedFileURL
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                CLIError.exit(.error, message: "Failed to write \(url.path): \(error.localizedDescription)")
            }
            return
        }
        CLIOutput.writeStdout(text)
    }
}
