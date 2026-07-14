import Foundation
import StorageCore

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
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
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
                  var line = String(data: data, encoding: .utf8) else {
                return
            }
            line += "\n"
            if fileManager.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let payload = line.data(using: .utf8) {
                    try handle.write(contentsOf: payload)
                }
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        } catch {
            // Best-effort only.
        }
    }

    public static func rotateIfNeeded(
        at url: URL,
        fileManager: FileManager = .default,
        maxBytes: Int = maxLogBytes
    ) {
        guard fileManager.fileExists(atPath: url.path),
              let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxBytes else {
            return
        }
        let rotated = url.appendingPathExtension("1")
        try? fileManager.removeItem(at: rotated)
        try? fileManager.moveItem(at: url, to: rotated)
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
}
