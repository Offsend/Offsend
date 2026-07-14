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

    static func message(for error: HookManagerError) -> String {
        switch error {
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        case .hookAlreadyInstalled(let path):
            return "Hook already exists at \(path). Use --force to overwrite."
        case .hookNotInstalled(let path):
            return "No hook found at \(path)."
        case .hookModified(let path):
            return "Hook at \(path) was modified manually. Use --force to remove it."
        case .cliNotFound:
            return "Could not locate the offsend executable."
        case .writeFailed(let path, let details):
            return "Failed to write hook at \(path): \(details)"
        }
    }

    static func exit(for error: HookManagerError) -> Never {
        let code: OffsendExitCode
        switch error {
        case .notARepository, .cliNotFound, .writeFailed:
            code = .error
        case .hookAlreadyInstalled, .hookNotInstalled, .hookModified:
            code = .hookState
        }
        exit(code, message: message(for: error))
    }

    static func exit(for error: GitRepositoryError) -> Never {
        switch error {
        case .gitNotFound:
            exit(.error, message: "git executable not found.")
        case .notARepository(let path):
            exit(.error, message: "Not a git repository: \(path)")
        case .commandFailed(let command, let output):
            exit(.error, message: "git command failed: \(command)\n\(output)")
        case .unsafeRelativePath(let path):
            exit(.error, message: "Refusing unsafe staged path: \(path)")
        }
    }
}
