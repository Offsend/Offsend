import Foundation

public struct SealCopyWriteResult: Equatable, Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

/// Writes sealed prompt text to a private temp file (mode 0600).
public enum SealCopyStore {
    public static func write(
        _ sealedText: String,
        fileManager: FileManager = .default
    ) throws -> SealCopyWriteResult {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("offsend-seal", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let url = directory.appendingPathComponent("sealed-\(UUID().uuidString).txt")
        try sealedText.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

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
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else {
                continue
            }
            if now.timeIntervalSince(modified) > maxAge {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
