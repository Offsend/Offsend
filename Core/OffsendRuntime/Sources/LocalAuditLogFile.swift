import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// File handling shared by Offsend's append-only local logs: a 0600 file inside a
/// 0700 directory, an append that refuses to follow symlinks, and size-capped
/// rotation. Kept in one place so a permission fix cannot land in one log and be
/// forgotten in the other.
enum LocalAuditLogFile {
    static let maxLogBytes = 256 * 1024

    /// Appends one JSON object as a line. Best-effort throughout: a log write must
    /// never fail the gate that produced it.
    static func appendJSONLine(
        _ object: [String: Any],
        to url: URL,
        fileManager: FileManager = .default,
        maxBytes: Int = maxLogBytes
    ) {
        do {
            try ensurePrivateDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
            rotateIfNeeded(at: url, fileManager: fileManager, maxBytes: maxBytes)
            guard
                let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                let line = String(data: data, encoding: .utf8),
                let payload = (line + "\n").data(using: .utf8)
            else {
                return
            }
            try appendSecurely(payload, to: url)
        } catch {
            // Best-effort only.
        }
    }

    static func rotateIfNeeded(
        at url: URL,
        fileManager: FileManager = .default,
        maxBytes: Int = maxLogBytes
    ) {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxBytes else {
            return
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let rotated = url.appendingPathExtension("1")
        try? fileManager.removeItem(at: rotated)
        if (try? fileManager.moveItem(at: url, to: rotated)) != nil {
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rotated.path)
        }
    }

    /// Bounds length and rewrites the home directory so a log line cannot leak a
    /// full local path. Never used to sanitize secret *values* — those are not
    /// written at all.
    static func sanitize(_ text: String, limit: Int = 120) -> String {
        let trimmed = String(text.prefix(limit))
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return trimmed }
        return trimmed.replacingOccurrences(of: home, with: "~")
    }

    static func readLines(
        from url: URL,
        maxLines: Int,
        fileManager: FileManager = .default
    ) -> [String] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).suffix(maxLines).map(String.init)
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
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func appendSecurely(_ data: Data, to url: URL) throws {
        let descriptor = open(
            url.path,
            O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try handle.write(contentsOf: data)
        try handle.close()
    }
}
