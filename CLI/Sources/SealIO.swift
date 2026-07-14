import Foundation
import OffsendRuntime
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum SealIO {
    static let maxInputBytes = 2 * 1024 * 1024

    private enum IOError: LocalizedError {
        case inputTooLarge(path: String, maxBytes: Int)
        case invalidUTF8(path: String)
        case outputExists(path: String)
        case temporaryFile(path: String)
        case replaceFailed(path: String, details: String)

        var errorDescription: String? {
            switch self {
            case .inputTooLarge(let path, let maxBytes):
                return "\(path) exceeds \(maxBytes) bytes."
            case .invalidUTF8(let path):
                return "\(path) is not valid UTF-8."
            case .outputExists(let path):
                return "Output already exists at \(path). Use --force to replace it."
            case .temporaryFile(let path):
                return "Could not create temporary output file at \(path)."
            case .replaceFailed(let path, let details):
                return "Could not replace output at \(path): \(details)"
            }
        }
    }

    static func readInput(path: String?, workingDirectory: URL) -> String {
        if let path {
            let url = URL(fileURLWithPath: path, relativeTo: workingDirectory).standardizedFileURL
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var data = Data()
                while data.count <= maxInputBytes {
                    let remaining = maxInputBytes + 1 - data.count
                    guard let chunk = try handle.read(upToCount: min(64 * 1024, remaining)),
                          !chunk.isEmpty else {
                        break
                    }
                    data.append(chunk)
                }
                guard data.count <= maxInputBytes else {
                    throw IOError.inputTooLarge(path: url.path, maxBytes: maxInputBytes)
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    throw IOError.invalidUTF8(path: url.path)
                }
                return text
            } catch {
                CLIError.exit(.error, message: "Failed to read \(url.path): \(error.localizedDescription)")
            }
        }

        do {
            return try CLIStdin.readUTF8(maxBytes: maxInputBytes)
        } catch let error as CLIStdin.ReadError {
            if case .tty = error {
                CLIError.exit(.error, message: "Provide a file path or pipe text on stdin.")
            }
            CLIError.exit(.error, message: error.message)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }
    }

    static func writeOutput(
        _ text: String,
        to outputPath: String?,
        workingDirectory: URL,
        force: Bool
    ) {
        if let outputPath {
            let url = URL(fileURLWithPath: outputPath, relativeTo: workingDirectory).standardizedFileURL
            do {
                try writeFileAtomically(Data(text.utf8), to: url, force: force)
            } catch {
                CLIError.exit(.error, message: "Failed to write \(url.path): \(error.localizedDescription)")
            }
            return
        }
        CLIOutput.writeStdout(text)
    }

    private static func writeFileAtomically(_ data: Data, to url: URL, force: Bool) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).offsend-\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: tempURL) }

        guard fileManager.createFile(
            atPath: tempURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw IOError.temporaryFile(path: tempURL.path)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)

        if force {
            try replaceItem(at: url, with: tempURL)
            return
        }

        do {
            try fileManager.linkItem(at: tempURL, to: url)
            try? fileManager.removeItem(at: tempURL)
        } catch {
            if (try? fileManager.attributesOfItem(atPath: url.path)) != nil {
                throw IOError.outputExists(path: url.path)
            }
            throw error
        }
    }

    private static func replaceItem(at destination: URL, with source: URL) throws {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                #if canImport(Darwin)
                Darwin.rename(sourcePath, destinationPath)
                #elseif canImport(Glibc)
                Glibc.rename(sourcePath, destinationPath)
                #else
                -1
                #endif
            }
        }
        guard result == 0 else {
            #if canImport(Darwin) || canImport(Glibc)
            let details = String(cString: strerror(errno))
            #else
            let details = "unsupported platform"
            #endif
            throw IOError.replaceFailed(path: destination.path, details: details)
        }
    }
}
