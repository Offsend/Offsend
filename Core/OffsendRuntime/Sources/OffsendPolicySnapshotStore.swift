#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import StorageCore

public struct OffsendPolicySnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let repositoryPath: String
    public let configHash: String
    public let trustedAt: Date

    public init(
        version: Int = 1,
        repositoryPath: String,
        configHash: String,
        trustedAt: Date = Date()
    ) {
        self.version = version
        self.repositoryPath = repositoryPath
        self.configHash = configHash
        self.trustedAt = trustedAt
    }
}

public enum OffsendPolicySnapshotStatus: Equatable, Sendable {
    case missing
    case trusted(OffsendPolicySnapshot)
    case drift(OffsendPolicySnapshot, reason: String)
    case invalidSnapshot(reason: String)

    public var isTrusted: Bool {
        if case .trusted = self { return true }
        return false
    }

    public var hasSnapshot: Bool {
        if case .missing = self { return false }
        return true
    }
}

public enum OffsendPolicySnapshotError: Error, Equatable, LocalizedError {
    case configMissing(path: String)
    case configInvalid(message: String)
    case readFailed(path: String)
    case writeFailed(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .configMissing(let path):
            return "No \(ProjectConfigLoader.filename) found at \(path)."
        case .configInvalid(let message):
            return "Cannot trust invalid \(ProjectConfigLoader.filename): \(message)"
        case .readFailed(let path):
            return "Failed to read \(path)."
        case .writeFailed(let path, let message):
            return "Failed to write trusted policy snapshot at \(path): \(message)"
        }
    }
}

/// User-local trust anchor for the repository policy consumed by editor gates.
/// The snapshot intentionally lives outside the workspace so an agent confined
/// to repository writes cannot approve its own policy changes.
public struct OffsendPolicySnapshotStore: Sendable {
    private static let snapshotVersion = 1

    private let fileManager: FileManager
    private let gitResolver: GitRepositoryResolver
    private let storageRoot: URL

    public init(
        fileManager: FileManager = .default,
        gitResolver: GitRepositoryResolver = GitRepositoryResolver(),
        storageRoot: URL? = nil
    ) {
        self.fileManager = fileManager
        self.gitResolver = gitResolver
        self.storageRoot = storageRoot
            ?? LocalStoreDirectory.defaultURL(fileManager: fileManager)
                .appendingPathComponent("policy-snapshots", isDirectory: true)
    }

    @discardableResult
    public func trust(directory: URL, now: Date = Date()) throws -> OffsendPolicySnapshot {
        let root = repositoryRoot(for: directory)
        let configURL = root.appendingPathComponent(ProjectConfigLoader.filename)
        guard fileManager.fileExists(atPath: configURL.path) else {
            throw OffsendPolicySnapshotError.configMissing(path: configURL.path)
        }
        do {
            guard try ProjectConfigLoader(fileManager: fileManager, gitResolver: gitResolver)
                .load(from: root) != nil else {
                throw OffsendPolicySnapshotError.configMissing(path: configURL.path)
            }
        } catch let error as OffsendPolicySnapshotError {
            throw error
        } catch {
            throw OffsendPolicySnapshotError.configInvalid(message: error.localizedDescription)
        }

        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw OffsendPolicySnapshotError.readFailed(path: configURL.path)
        }
        let snapshot = OffsendPolicySnapshot(
            version: Self.snapshotVersion,
            repositoryPath: root.path,
            configHash: Self.sha256(data),
            trustedAt: now
        )
        try write(snapshot, to: snapshotURL(forRepositoryRoot: root))
        return snapshot
    }

    public func status(directory: URL) -> OffsendPolicySnapshotStatus {
        let root = repositoryRoot(for: directory)
        let url = snapshotURL(forRepositoryRoot: root)
        guard fileManager.fileExists(atPath: url.path) else { return .missing }

        let snapshot: OffsendPolicySnapshot
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(OffsendPolicySnapshot.self, from: data)
        } catch {
            return .invalidSnapshot(reason: "snapshot unreadable or invalid")
        }
        guard snapshot.version == Self.snapshotVersion, snapshot.repositoryPath == root.path else {
            return .invalidSnapshot(reason: "snapshot metadata mismatch")
        }

        let configURL = root.appendingPathComponent(ProjectConfigLoader.filename)
        guard fileManager.fileExists(atPath: configURL.path) else {
            return .drift(snapshot, reason: "project policy is missing")
        }
        guard let data = try? Data(contentsOf: configURL) else {
            return .drift(snapshot, reason: "project policy is unreadable")
        }
        guard Self.sha256(data) == snapshot.configHash else {
            return .drift(snapshot, reason: "project policy changed after explicit trust")
        }
        return .trusted(snapshot)
    }

    public func snapshotURL(directory: URL) -> URL {
        snapshotURL(forRepositoryRoot: repositoryRoot(for: directory))
    }

    public func remove(directory: URL) throws {
        let url = snapshotURL(directory: directory)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func repositoryRoot(for directory: URL) -> URL {
        let standardized = directory.standardizedFileURL
        return ((try? gitResolver.repositoryRoot(startingAt: standardized)) ?? standardized)
            .standardizedFileURL
    }

    private func snapshotURL(forRepositoryRoot root: URL) -> URL {
        let identifier = Self.sha256(Data(root.path.utf8))
        return storageRoot.appendingPathComponent("\(identifier).json")
    }

    private func write(_ snapshot: OffsendPolicySnapshot, to url: URL) throws {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw OffsendPolicySnapshotError.writeFailed(path: url.path, message: error.localizedDescription)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
