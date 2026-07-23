import Foundation
import StorageCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Append-only debug log for AI-editor hooks. Never writes secret values.
public enum HookDebugLog {
    public static var defaultLogURL: URL {
        LocalStoreDirectory.defaultURL().appendingPathComponent("hook-debug.log")
    }

    /// Rotate when the log exceeds this many bytes.
    public static let maxLogBytes = 512 * 1024

    public struct Entry: Equatable, Sendable {
        public let adapter: String
        public let policy: String
        public let findingCount: Int
        public let findingTypes: [String]
        public let exitCode: Int32
        public let latencyMs: Int
        public let error: String?

        public init(
            adapter: String,
            policy: String,
            findingCount: Int,
            findingTypes: [String],
            exitCode: Int32,
            latencyMs: Int,
            error: String? = nil
        ) {
            self.adapter = adapter
            self.policy = policy
            self.findingCount = findingCount
            self.findingTypes = findingTypes
            self.exitCode = exitCode
            self.latencyMs = latencyMs
            self.error = error
        }
    }

    public static func append(
        _ entry: Entry,
        to url: URL = defaultLogURL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) {
        do {
            try ensurePrivateDirectory(
                url.deletingLastPathComponent(),
                fileManager: fileManager
            )
            rotateIfNeeded(at: url, fileManager: fileManager)

            var object: [String: Any] = [
                "ts": ISO8601DateFormatter().string(from: now),
                "adapter": entry.adapter,
                "policy": entry.policy,
                "findingCount": entry.findingCount,
                "findingTypes": entry.findingTypes,
                "exitCode": entry.exitCode,
                "latencyMs": entry.latencyMs,
            ]
            if let error = entry.error {
                object["error"] = sanitizeLogText(error)
            }
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  let line = String(data: data, encoding: .utf8),
                  let payload = (line + "\n").data(using: .utf8) else {
                return
            }
            try appendSecurely(payload, to: url)
        } catch {
            // Best-effort only.
        }
    }

    public static func rotateIfNeeded(
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

    /// Redact home-directory prefixes from debug log fields.
    static func sanitizeLogText(_ text: String) -> String {
        let home = NSHomeDirectory()
        var sanitized = text
        if !home.isEmpty {
            sanitized = sanitized.replacingOccurrences(of: home, with: "~")
        }
        return sanitized
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
            throw CocoaError(.fileWriteInvalidFileName)
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
