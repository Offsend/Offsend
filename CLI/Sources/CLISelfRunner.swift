import ArgumentParser
import Foundation
import OffsendRuntime

/// Runs another `offsend` subcommand in-process via a child process using this executable.
enum CLISelfRunner {
    static func executablePath() -> String? {
        if let resolved = OffsendCLILocator.resolvedExecutablePath() {
            return resolved
        }
        let argv0 = CommandLine.arguments[0]
        if argv0.contains("/") {
            return URL(fileURLWithPath: argv0).standardizedFileURL.path
        }
        return argv0
    }

    @discardableResult
    static func run(_ arguments: [String], directory: String? = nil) throws -> Int32 {
        guard let executable = executablePath() else {
            CLIError.exit(.error, message: "Could not locate the offsend executable.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func runOrThrow(_ arguments: [String], directory: String? = nil) throws {
        let code = try run(arguments, directory: directory)
        if code != 0 {
            throw ExitCode(code)
        }
    }
}
