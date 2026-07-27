import Crypto
import Foundation
import StorageCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ArtifactProvenanceEntry: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let repositoryID: String
    public let relativePath: String
    public let pathHash: String
    public let artifactKind: ExecutableArtifactKind
    public let adapter: String
    public let toolName: String
    public let outcome: String
    public let contentHash: String?
    /// SHA-256 of the preceding ledger line, so removing or rewriting an entry
    /// breaks the chain instead of leaving no trace. `nil` for the first entry
    /// of a log file and for entries written before chaining existed.
    public let previousHash: String?

    public init(
        timestamp: Date,
        repositoryID: String,
        relativePath: String,
        pathHash: String,
        artifactKind: ExecutableArtifactKind,
        adapter: String,
        toolName: String,
        outcome: String,
        contentHash: String?,
        previousHash: String? = nil
    ) {
        self.timestamp = timestamp
        self.repositoryID = repositoryID
        self.relativePath = relativePath
        self.pathHash = pathHash
        self.artifactKind = artifactKind
        self.adapter = adapter
        self.toolName = toolName
        self.outcome = outcome
        self.contentHash = contentHash
        self.previousHash = previousHash
    }
}

public enum ArtifactProvenanceChainStatus: Equatable, Sendable {
    /// Every chained entry matches the line before it.
    case intact
    /// Nothing to verify yet: empty log, or only entries written before chaining.
    case unverifiable
    /// The entry at this 1-based line does not follow the line before it.
    case broken(line: Int)
    /// Fewer entries remain than were written. Cutting the log at either end
    /// leaves the surviving lines chained to one another, so only a count kept
    /// outside the log can show that something is gone.
    case truncated(expected: Int, found: Int)
}

/// Length and tail hash of the log, written beside it under the same lock.
/// The in-file chain cannot see a log cut at either end: the first line has
/// nothing to be checked against, and the last line has no successor to check
/// it. This is what those two ends are checked against.
private struct ArtifactProvenanceAnchor: Codable {
    let entryCount: Int
    let lastLineHash: String
}

/// Metadata-only, append-only record of agent changes to executable trust
/// surfaces. The ledger never stores file contents or absolute repository paths.
public struct ArtifactProvenanceLedger: Sendable {
    public static let maxLogBytes = 512 * 1024
    public static let maxHashBytes = 2 * 1024 * 1024

    private let fileManager: FileManager
    public let logURL: URL

    public init(fileManager: FileManager = .default, logURL: URL? = nil) {
        self.fileManager = fileManager
        self.logURL = logURL
            ?? LocalStoreDirectory.defaultURL(fileManager: fileManager)
                .appendingPathComponent("artifact-provenance.jsonl")
    }

    @discardableResult
    public func record(
        path: String,
        projectRoot: URL,
        adapter: CheckHookAdapter,
        toolName: String,
        classifier: ExecutableArtifactClassifier? = nil,
        now: Date = Date()
    ) -> ArtifactProvenanceEntry? {
        let root = projectRoot.standardizedFileURL
        let classifier = classifier ?? ExecutableArtifactClassifier(projectRoot: root)
        guard let artifact = classifier.classify(path: path) else { return nil }
        let absolute = URL(fileURLWithPath: artifact.path).standardizedFileURL
        // Hashed before the lock is taken: the written file can be megabytes,
        // and hashing it under the lock would serialize unrelated hooks.
        let writtenHash = contentHash(at: absolute)
        return withLedgerLock {
            // Rotation first, so the entry chains onto the log it actually
            // lands in and the anchor counts that same log.
            rotateIfNeeded()
            let existing = rawLines()
            let entry = ArtifactProvenanceEntry(
                timestamp: now,
                repositoryID: Self.sha256(Data(root.path.utf8)),
                relativePath: safeRelativePath(absolute, root: root, kind: artifact.kind),
                pathHash: Self.sha256(Data(absolute.path.utf8)),
                artifactKind: artifact.kind,
                adapter: adapter.rawValue,
                toolName: toolName,
                outcome: "changed",
                contentHash: writtenHash,
                previousHash: existing.last.map { Self.sha256(Data($0.utf8)) }
            )
            append(entry, existingLineCount: existing.count)
            return entry
        }
    }

    /// Walks the log for an entry that does not follow the line before it, then
    /// checks the log's two ends against the anchor. Detects a removed,
    /// reordered, or rewritten entry and a log cut at either end; it cannot
    /// detect an attacker who rewrites both the log and the anchor, because
    /// both live on the same machine.
    public func verifyChain() -> ArtifactProvenanceChainStatus {
        let lines = rawLines()
        var sawChainedEntry = false
        if lines.count > 1 {
            for index in 1..<lines.count {
                guard let entry = decode(lines[index]) else { continue }
                guard let previousHash = entry.previousHash else { continue }
                sawChainedEntry = true
                if previousHash != Self.sha256(Data(lines[index - 1].utf8)) {
                    return .broken(line: index + 1)
                }
            }
        } else {
            sawChainedEntry = lines.first.flatMap(decode)?.previousHash != nil
        }
        guard let anchor = readAnchor() else {
            return sawChainedEntry ? .intact : .unverifiable
        }
        if lines.count < anchor.entryCount {
            return .truncated(expected: anchor.entryCount, found: lines.count)
        }
        // A log longer than the anchor means an append whose anchor update did
        // not land — an older build, or a hook killed between the two writes.
        // Only a shorter log proves removal, so the tail is checked just when
        // the lengths agree.
        if lines.count == anchor.entryCount,
           let last = lines.last,
           Self.sha256(Data(last.utf8)) != anchor.lastLineHash {
            return .broken(line: lines.count)
        }
        return .intact
    }

    private func rawLines() -> [String] {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private func decode(_ line: String) -> ArtifactProvenanceEntry? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ArtifactProvenanceEntry.self, from: Data(line.utf8))
    }

    public func recentEntries(
        repositoryRoot: URL,
        since: Date = Date().addingTimeInterval(-30 * 24 * 60 * 60)
    ) -> [ArtifactProvenanceEntry] {
        let repositoryID = Self.sha256(Data(repositoryRoot.standardizedFileURL.path.utf8))
        return rawLines().compactMap(decode)
            .filter { $0.repositoryID == repositoryID && $0.timestamp >= since }
    }

    /// Serializes reading the chain head and appending the entry that points at
    /// it. One post-write hook runs per edited file, so a multi-file edit starts
    /// several processes at once; without this they claim the same predecessor
    /// and `verifyChain()` reports the result as tampering. A lock file is used
    /// rather than the log itself so that rotation stays inside the same
    /// critical section. Failing to lock falls through to an unlocked write:
    /// provenance is best-effort and must not drop records.
    private func withLedgerLock<T>(_ body: () -> T) -> T {
        try? ensurePrivateDirectory(logURL.deletingLastPathComponent())
        let descriptor = open(
            logURL.appendingPathExtension("lock").path,
            O_WRONLY | O_CREAT | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { return body() }
        defer { close(descriptor) }
        var status: Int32
        repeat {
            status = flock(descriptor, LOCK_EX)
        } while status != 0 && errno == EINTR
        return body()
    }

    /// Rotation has already run, so `existingLineCount` is the length of the log
    /// this entry extends.
    private func append(_ entry: ArtifactProvenanceEntry, existingLineCount: Int) {
        do {
            try ensurePrivateDirectory(logURL.deletingLastPathComponent())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let line = try encoder.encode(entry)
            var data = line
            data.append(0x0A)
            try appendSecurely(data)
            writeAnchor(
                ArtifactProvenanceAnchor(
                    entryCount: existingLineCount + 1,
                    lastLineHash: Self.sha256(line)
                )
            )
        } catch {
            // Provenance is best-effort and must not break editor workflows.
        }
    }

    private var anchorURL: URL {
        logURL.appendingPathExtension("anchor")
    }

    private func writeAnchor(_ anchor: ArtifactProvenanceAnchor) {
        guard let data = try? JSONEncoder().encode(anchor) else { return }
        try? data.write(to: anchorURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: anchorURL.path)
    }

    private func readAnchor() -> ArtifactProvenanceAnchor? {
        guard let data = try? Data(contentsOf: anchorURL) else { return nil }
        return try? JSONDecoder().decode(ArtifactProvenanceAnchor.self, from: data)
    }

    private func safeRelativePath(
        _ url: URL,
        root: URL,
        kind: ExecutableArtifactKind
    ) -> String {
        let prefix = root.path + "/"
        if url.path.hasPrefix(prefix) {
            return String(url.path.dropFirst(prefix.count))
        }
        return "<external>/\(kind.rawValue)/\(url.lastPathComponent)"
    }

    private func contentHash(at url: URL) -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue <= Self.maxHashBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return Self.sha256(data)
    }

    private func ensurePrivateDirectory(_ directory: URL) throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let attributes = try fileManager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func rotateIfNeeded() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue > Self.maxLogBytes else {
            return
        }
        let rotated = logURL.appendingPathExtension("1")
        try? fileManager.removeItem(at: rotated)
        if (try? fileManager.moveItem(at: logURL, to: rotated)) != nil {
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rotated.path)
            // The anchor describes the log that just moved away. Dropping it
            // keeps a failed append from looking like a truncated log.
            try? fileManager.removeItem(at: anchorURL)
        }
    }

    private func appendSecurely(_ data: Data) throws {
        let descriptor = open(
            logURL.path,
            O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0, fchmod(descriptor, mode_t(0o600)) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw CocoaError(.fileWriteNoPermission)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
