import Foundation
import StorageCore

/// Append-only local log of secrets seen in agent shell output.
///
/// Records the command and the detector types only. Secret **values** are never
/// written: by the time this log exists the value is already in the model's
/// context, so copying it to disk would add a second exposure without adding any
/// information the user needs in order to rotate.
public enum ShellOutputAuditLog {
    public static var defaultLogURL: URL {
        LocalStoreDirectory.defaultURL().appendingPathComponent("shell-output-audit.log")
    }

    public struct Entry: Equatable, Sendable {
        public let command: String
        public let secretTypes: [String]
        /// Whether the editor reported the command as sandboxed, so a later
        /// review can tell an unsandboxed leak from a contained one.
        public let sandboxed: Bool?

        public init(command: String, secretTypes: [String], sandboxed: Bool? = nil) {
            self.command = command
            self.secretTypes = secretTypes
            self.sandboxed = sandboxed
        }
    }

    public struct HitSummary: Equatable, Sendable {
        public let command: String
        public let count: Int
        public let secretTypes: [String]

        public init(command: String, count: Int, secretTypes: [String]) {
            self.command = command
            self.count = count
            self.secretTypes = secretTypes
        }
    }

    public static func append(
        _ entry: Entry,
        to url: URL = defaultLogURL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) {
        var object: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: now),
            "kind": "shell_output",
            "command": LocalAuditLogFile.sanitize(entry.command, limit: 200),
            "secretTypes": entry.secretTypes.map { LocalAuditLogFile.sanitize($0) }.sorted(),
        ]
        if let sandboxed = entry.sandboxed {
            object["sandboxed"] = sandboxed
        }
        LocalAuditLogFile.appendJSONLine(object, to: url, fileManager: fileManager)
    }

    /// Newest-first summaries grouped by command, capped.
    public static func recentSummaries(
        limit: Int = 8,
        maxLines: Int = 2_000,
        from url: URL = defaultLogURL,
        fileManager: FileManager = .default
    ) -> [HitSummary] {
        var order: [String] = []
        var buckets: [String: HitSummary] = [:]
        let lines = LocalAuditLogFile.readLines(
            from: url,
            maxLines: maxLines,
            fileManager: fileManager
        )
        for line in lines.reversed() {
            guard let entry = parseLine(line) else { continue }
            if let existing = buckets[entry.command] {
                buckets[entry.command] = HitSummary(
                    command: existing.command,
                    count: existing.count + 1,
                    secretTypes: Array(Set(existing.secretTypes + entry.secretTypes)).sorted()
                )
            } else {
                order.append(entry.command)
                buckets[entry.command] = HitSummary(
                    command: entry.command,
                    count: 1,
                    secretTypes: entry.secretTypes
                )
            }
            if order.count >= limit { break }
        }
        return order.prefix(limit).compactMap { buckets[$0] }
    }

    private static func parseLine(_ line: String) -> Entry? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = object["command"] as? String else {
            return nil
        }
        return Entry(
            command: command,
            secretTypes: (object["secretTypes"] as? [String]) ?? [],
            sandboxed: object["sandboxed"] as? Bool
        )
    }
}
