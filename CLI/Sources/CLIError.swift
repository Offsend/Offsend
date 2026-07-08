import ArgumentParser
import Foundation
import OffsendRuntime
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum CLIError {
    static func exit(_ code: OffsendExitCode, message: String? = nil) -> Never {
        if let message {
            fputs("error: \(message)\n", stderr)
        }
        #if canImport(Darwin)
        Darwin.exit(code.rawValue)
        #elseif canImport(Glibc)
        Glibc.exit(code.rawValue)
        #else
        fatalError("Unsupported platform")
        #endif
    }

    static func exit(for error: HookManagerError) -> Never {
        let message: String
        let code: OffsendExitCode
        switch error {
        case .notARepository(let path):
            message = "Not a git repository: \(path)"
            code = .error
        case .hookAlreadyInstalled(let path):
            message = "Hook already exists at \(path). Use --force to overwrite."
            code = .hookState
        case .hookNotInstalled(let path):
            message = "No hook found at \(path)."
            code = .hookState
        case .hookModified(let path):
            message = "Hook at \(path) was modified manually. Use --force to remove it."
            code = .hookState
        case .cliNotFound:
            message = "Could not locate the offsend executable."
            code = .error
        case .writeFailed(let path, let details):
            message = "Failed to write hook at \(path): \(details)"
            code = .error
        }
        exit(code, message: message)
    }

    static func exit(for error: GitRepositoryError) -> Never {
        switch error {
        case .gitNotFound:
            exit(.error, message: "git executable not found.")
        case .notARepository(let path):
            exit(.error, message: "Not a git repository: \(path)")
        case .commandFailed(let command, let output):
            exit(.error, message: "git command failed: \(command)\n\(output)")
        }
    }
}
