import Foundation

enum ExecutableLocator {
    static func which(
        _ command: String,
        fileManager: FileManager = .default,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> String? {
        if command.contains("/") {
            let path = URL(fileURLWithPath: command).standardizedFileURL.path
            return fileManager.isExecutableFile(atPath: path) ? path : nil
        }

        if let path = searchPATH(command, fileManager: fileManager, pathEnvironment: pathEnvironment) {
            return path
        }

        return runWhich(command, fileManager: fileManager)
    }

    static func defaultGitExecutable(fileManager: FileManager = .default) -> String {
        which("git", fileManager: fileManager) ?? "/usr/bin/git"
    }

    private static func searchPATH(
        _ command: String,
        fileManager: FileManager,
        pathEnvironment: String?
    ) -> String? {
        let directories = (pathEnvironment ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)

        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(command).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func runWhich(_ command: String, fileManager: FileManager) -> String? {
        for whichPath in ["/usr/bin/which", "/bin/which"] {
            guard fileManager.isExecutableFile(atPath: whichPath) else { continue }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: whichPath)
            process.arguments = [command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                continue
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { continue }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty, fileManager.isExecutableFile(atPath: path) else {
                continue
            }
            return path
        }
        return nil
    }
}
