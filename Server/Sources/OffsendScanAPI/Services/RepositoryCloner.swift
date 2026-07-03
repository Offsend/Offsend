import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments

        // Never prompt for credentials (private/nonexistent repos) and never pull LFS blobs.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_LFS_SKIP_SMUDGE"] = "1"
        process.environment = environment

        let stderr = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr

        // Drain stderr continuously so a chatty git can't fill the 64KB pipe
        // buffer and stall while nobody is reading.
        let stderrCollector = PipeCollector()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrCollector.append(chunk)
            }
        }

        // The handler must be installed before run() so a fast exit can't be missed.
        let (exitStatuses, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { process in
            exitContinuation.yield(process.terminationStatus)
            exitContinuation.finish()
        }

        try process.run()

        let timeout = self.timeout
        // nil means the timeout fired before the process exited.
        let status: Int32? = await withTaskGroup(of: Int32?.self) { group in
            group.addTask {
                var iterator = exitStatuses.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard let status else {
            terminateWithEscalation(process)
            throw RepositoryCloneError.timedOut
        }

        guard status == 0 else {
            let message = String(data: stderrCollector.contents, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RepositoryCloneError.failed(message?.isEmpty == false ? message! : "git clone failed")
        }
    }

    /// SIGTERM first; if git ignores it, SIGKILL after a short grace period.
    private func terminateWithEscalation(_ process: Process) {
        process.terminate()
        let pid = process.processIdentifier
        Task {
            for _ in 0..<50 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}

/// Thread-safe accumulator for pipe output; readabilityHandler runs off-thread.
private final class PipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var contents: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
