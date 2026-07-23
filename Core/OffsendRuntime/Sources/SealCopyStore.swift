import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum SealCopyStoreError: Error, Equatable {
    case unsafeDirectory
    case createFailed
    case verificationFailed
}

public struct SealCopyWriteResult: Equatable, Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

/// Writes sealed prompt text to a private temp file (mode 0600).
public enum SealCopyStore {
    /// Directory sealed copies live in. Files under it are still content-scanned
    /// by the read gate; directory membership is not a trust boundary.
    public static func directoryURL(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("offsend-seal", isDirectory: true)
    }

    public static func write(
        _ sealedText: String,
        fileManager: FileManager = .default
    ) throws -> SealCopyWriteResult {
        let directory = directoryURL(fileManager: fileManager)
        return try write(sealedText, in: directory, fileManager: fileManager)
    }

    static func write(
        _ sealedText: String,
        in directory: URL,
        fileManager: FileManager = .default
    ) throws -> SealCopyWriteResult {
        try ensurePrivateDirectory(directory, fileManager: fileManager)

        let directoryDescriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directoryDescriptor >= 0 else { throw SealCopyStoreError.unsafeDirectory }
        defer { _ = close(directoryDescriptor) }
        // Capture the directory identity from the descriptor itself (no
        // path-based TOCTOU window between the check and the writes below).
        var directoryStat = stat()
        guard fstat(directoryDescriptor, &directoryStat) == 0 else {
            throw SealCopyStoreError.unsafeDirectory
        }
        guard fchmod(directoryDescriptor, mode_t(0o700)) == 0 else {
            throw SealCopyStoreError.unsafeDirectory
        }

        let filename = "sealed-\(UUID().uuidString).txt"
        let descriptor = openat(
            directoryDescriptor,
            filename,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw SealCopyStoreError.createFailed }

        var removeOnFailure = true
        defer {
            if removeOnFailure {
                _ = unlinkat(directoryDescriptor, filename, 0)
            }
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data(sealedText.utf8))
        try handle.synchronize()
        try handle.close()

        let currentDirectoryAttributes = try fileManager.attributesOfItem(atPath: directory.path)
        guard sameFile(directoryStat, currentDirectoryAttributes) else {
            throw SealCopyStoreError.unsafeDirectory
        }

        let url = directory.appendingPathComponent(filename)
        let fileAttributes = try fileManager.attributesOfItem(atPath: url.path)
        guard fileAttributes[.type] as? FileAttributeType == .typeRegular else {
            throw SealCopyStoreError.verificationFailed
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        removeOnFailure = false

        // Best-effort cleanup of files older than 1 hour.
        cleanupExpired(in: directory, fileManager: fileManager, maxAge: 3600)

        return SealCopyWriteResult(fileURL: url)
    }

    public static func cleanupExpired(
        in directory: URL,
        fileManager: FileManager = .default,
        maxAge: TimeInterval,
        now: Date = Date()
    ) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in contents {
            guard url.lastPathComponent.hasPrefix("sealed-"),
                  url.pathExtension == "txt",
                  let values = try? url.resourceValues(forKeys: [
                      .contentModificationDateKey,
                      .isRegularFileKey,
                      .isSymbolicLinkKey,
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let modified = values.contentModificationDate else {
                continue
            }
            if now.timeIntervalSince(modified) > maxAge {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private static func ensurePrivateDirectory(
        _ directory: URL,
        fileManager: FileManager
    ) throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let attributes = try fileManager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw SealCopyStoreError.unsafeDirectory
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func sameFile(
        _ directoryStat: stat,
        _ attributes: [FileAttributeKey: Any]
    ) -> Bool {
        guard let fileNumber = attributes[.systemFileNumber] as? NSNumber,
              let systemNumber = attributes[.systemNumber] as? NSNumber else {
            return false
        }
        return fileNumber.uint64Value == UInt64(truncatingIfNeeded: directoryStat.st_ino)
            && systemNumber.uint64Value == UInt64(truncatingIfNeeded: directoryStat.st_dev)
    }
}
