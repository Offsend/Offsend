import Foundation

public enum GitRepositoryError: Error, Equatable, Sendable {
    case gitNotFound
    case notARepository(path: String)
    case commandFailed(command: String, output: String)
}

public struct GitRepositoryResolver: Sendable {
    private let fileManager: FileManager
    private let gitExecutable: String

    public init(
        fileManager: FileManager = .default,
        gitExecutable: String? = nil
    ) {
        self.fileManager = fileManager
        self.gitExecutable = gitExecutable ?? ExecutableLocator.defaultGitExecutable(fileManager: fileManager)
    }

    public func repositoryRoot(startingAt path: URL) throws -> URL {
        let standardized = path.standardizedFileURL
        var candidate = standardized
        if !fileManager.fileExists(atPath: candidate.path, isDirectory: nil) {
            candidate = standardized.deletingLastPathComponent()
        }

        while true {
            let gitPath = candidate.appendingPathComponent(".git").path
            if fileManager.fileExists(atPath: gitPath) {
                return candidate
            }
            // Stop at the filesystem root explicitly: deletingLastPathComponent()
            // on "/" can yield "/.." and loop forever.
            if candidate.path == "/" {
                throw GitRepositoryError.notARepository(path: standardized.path)
            }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            if parent.path == candidate.path {
                throw GitRepositoryError.notARepository(path: standardized.path)
            }
            candidate = parent
        }
    }

    public func stagedFileURLs(in repositoryRoot: URL) throws -> [URL] {
        try stagedRelativePaths(in: repositoryRoot).map { path in
            repositoryRoot.appendingPathComponent(path).standardizedFileURL
        }
    }

    public func stagedRelativePaths(in repositoryRoot: URL) throws -> [String] {
        let output = try runGit(
            arguments: ["diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"],
            workingDirectory: repositoryRoot
        )
        guard !output.isEmpty else { return [] }

        return output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
    }

    /// Reads the staged (index) content of a file, which may differ from the working tree.
    public func stagedFileData(relativePath: String, in repositoryRoot: URL) throws -> Data {
        try runGitData(
            arguments: ["cat-file", "blob", ":\(relativePath)"],
            workingDirectory: repositoryRoot
        )
    }

    /// Writes staged blob contents into `destination`, mirroring repository-relative paths.
    /// Returns the URLs of the materialized files in the same order as the staged paths.
    public func exportStagedFiles(in repositoryRoot: URL, to destination: URL) throws -> [URL] {
        let relativePaths = try stagedRelativePaths(in: repositoryRoot)
        var exported: [URL] = []
        exported.reserveCapacity(relativePaths.count)

        for relativePath in relativePaths {
            let data = try stagedFileData(relativePath: relativePath, in: repositoryRoot)
            let fileURL = destination.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL)
            exported.append(fileURL)
        }
        return exported
    }

    /// Resolves the hooks directory, honoring `core.hooksPath`, worktrees, and submodules.
    /// Falls back to `.git/hooks` when git cannot be invoked.
    public func hooksDirectory(in repositoryRoot: URL) -> URL {
        if let output = try? runGit(
            arguments: ["rev-parse", "--git-path", "hooks"],
            workingDirectory: repositoryRoot
        ) {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                if path.hasPrefix("/") {
                    return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
                }
                return repositoryRoot.appendingPathComponent(path, isDirectory: true).standardizedFileURL
            }
        }
        return repositoryRoot
            .appendingPathComponent(".git", isDirectory: true)
            .appendingPathComponent("hooks", isDirectory: true)
    }

    @discardableResult
    public func runGit(arguments: [String], workingDirectory: URL) throws -> String {
        let data = try runGitData(arguments: arguments, workingDirectory: workingDirectory)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func runGitData(arguments: [String], workingDirectory: URL) throws -> Data {
        guard fileManager.isExecutableFile(atPath: gitExecutable) else {
            throw GitRepositoryError.gitNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitExecutable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        // Drain pipes before waiting, otherwise git blocks once the pipe buffer
        // fills up (e.g. `cat-file blob` on a large staged file).
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let out = String(data: outData, encoding: .utf8) ?? ""
            let err = String(data: errData, encoding: .utf8) ?? ""
            let combined = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
            throw GitRepositoryError.commandFailed(
                command: ([gitExecutable] + arguments).joined(separator: " "),
                output: combined
            )
        }

        return outData
    }
}
