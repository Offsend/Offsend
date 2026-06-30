import Foundation

enum RepositoryCloneError: Error, Sendable, LocalizedError {
    case gitUnavailable(path: String)
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .gitUnavailable(path):
            "git executable not found at \(path)"
        case .timedOut:
            "Repository clone timed out."
        case let .failed(message):
            message
        }
    }
}

struct RepositoryCloner {
    let gitPath: String
    let timeout: Duration
    let fileManager: FileManager

    init(gitPath: String, timeout: Duration, fileManager: FileManager = .default) {
        self.gitPath = gitPath
        self.timeout = timeout
        self.fileManager = fileManager
    }

    func clone(repositoryURL: URL, into destination: URL) async throws {
        guard fileManager.isExecutableFile(atPath: gitPath) else {
            throw RepositoryCloneError.gitUnavailable(path: gitPath)
        }

        try? fileManager.removeItem(at: destination)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let cloneURL = RepositoryURLValidator.cloneURL(for: repositoryURL)
        try await runGit(
            arguments: [
                "clone",
                "--depth", "1",
                "--single-branch",
                "--no-recurse-submodules",
                cloneURL.absoluteString,
                destination.path,
            ]
        )
    }

    func removeClone(at url: URL) {
        try? fileManager.removeItem(at: url)
    }

    private func runGit(arguments: [String]) async throws {
        let gitPath = self.gitPath
        let timeout = self.timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(for: timeout)
                throw RepositoryCloneError.timedOut
            }
            group.addTask {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gitPath)
                process.arguments = arguments

                let stderr = Pipe()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = stderr

                try process.run()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    throw RepositoryCloneError.failed(message?.isEmpty == false ? message! : "git clone failed")
                }
            }
            try await group.next()
            group.cancelAll()
        }
    }
}
