import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

        if isatty(STDIN_FILENO) != 0 {
            CLIError.exit(.error, message: "Provide a file path or pipe text on stdin.")
        }

        var data = Data()
        while true {
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let count = read(STDIN_FILENO, &buffer, buffer.count)
            if count < 0 {
                CLIError.exit(.error, message: "Failed to read stdin.")
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            CLIError.exit(.error, message: "stdin is not valid UTF-8.")
        }
        return text
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
        // Avoid an extra trailing newline when the sealed/unsealed text already ends with one.
        if text.hasSuffix("\n") {
            print(text, terminator: "")
        } else {
            print(text)
        }
    }
}
