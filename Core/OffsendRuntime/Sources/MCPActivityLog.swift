import Foundation
import StorageCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Append-only local log of MCP gate events (server/tool + outcome only; never payloads).
/// Always written from MCP hooks so `offsend show` / `doctor` can suggest rules.
public enum MCPActivityLog {
    public static var defaultLogURL: URL {
        LocalStoreDirectory.defaultURL().appendingPathComponent("mcp-activity.log")
    }

    public static let maxLogBytes = 256 * 1024

    public struct Entry: Equatable, Sendable {
        public let kind: String
        public let server: String
        public let tool: String
        public let code: String
        public let secretTypes: [String]
        public let fieldsTransformed: Int

        public init(
            kind: String,
            server: String,
            tool: String,
            code: String,
            secretTypes: [String] = [],
            fieldsTransformed: Int = 0
        ) {
            self.kind = kind
            self.server = server
            self.tool = tool
            self.code = code
            self.secretTypes = secretTypes
            self.fieldsTransformed = fieldsTransformed
        }
    }

    /// Aggregated recent hit for show/doctor.
    public struct HitSummary: Equatable, Sendable {
        public let server: String
        public let tool: String
        public let kind: String
        public let count: Int
        public let lastCode: String
        public let secretTypes: [String]
        public let fieldsTransformed: Int

        public init(
            server: String,
            tool: String,
            kind: String,
            count: Int,
            lastCode: String,
            secretTypes: [String],
            fieldsTransformed: Int
        ) {
            self.server = server
            self.tool = tool
            self.kind = kind
            self.count = count
            self.lastCode = lastCode
            self.secretTypes = secretTypes
            self.fieldsTransformed = fieldsTransformed
        }

        public var label: String { "\(server)/\(tool)" }
    }

    public static func append(
        _ entry: Entry,
        to url: URL = defaultLogURL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) {
        do {
            try ensurePrivateDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
            rotateIfNeeded(at: url, fileManager: fileManager)

            var object: [String: Any] = [
                "ts": ISO8601DateFormatter().string(from: now),
                "kind": entry.kind,
                "server": sanitize(entry.server),
                "tool": sanitize(entry.tool),
                "code": sanitize(entry.code),
                "secretTypes": entry.secretTypes.map(sanitize).sorted(),
                "fieldsTransformed": entry.fieldsTransformed,
            ]
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

    /// Newest-first summaries, capped.
    public static func recentSummaries(
        limit: Int = 8,
        maxLines: Int = 2_000,
        from url: URL = defaultLogURL,
        fileManager: FileManager = .default
    ) -> [HitSummary] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let lines = text.split(whereSeparator: \.isNewline).suffix(maxLines)
        var order: [String] = []
        var buckets: [String: HitSummary] = [:]

        for line in lines.reversed() {
            guard let entry = parseLine(String(line)) else { continue }
            let key = "\(entry.kind)|\(entry.server)|\(entry.tool)"
            if var existing = buckets[key] {
                existing = HitSummary(
                    server: existing.server,
                    tool: existing.tool,
                    kind: existing.kind,
                    count: existing.count + 1,
                    lastCode: existing.lastCode,
                    secretTypes: Array(Set(existing.secretTypes + entry.secretTypes)).sorted(),
                    fieldsTransformed: max(existing.fieldsTransformed, entry.fieldsTransformed)
                )
                buckets[key] = existing
            } else {
                order.append(key)
                buckets[key] = HitSummary(
                    server: entry.server,
                    tool: entry.tool,
                    kind: entry.kind,
                    count: 1,
                    lastCode: entry.code,
                    secretTypes: entry.secretTypes,
                    fieldsTransformed: entry.fieldsTransformed
                )
            }
            if order.count >= limit, buckets.count >= limit { break }
        }

        return order.prefix(limit).compactMap { buckets[$0] }
    }

    /// Findings-only view (secrets / sealed / fields / policy denials).
    public static func recentFindingSummaries(
        limit: Int = 8,
        from url: URL = defaultLogURL,
        fileManager: FileManager = .default
    ) -> [HitSummary] {
        recentSummaries(limit: limit * 3, from: url, fileManager: fileManager)
            .filter { summary in
                summary.lastCode != "allow"
                    || !summary.secretTypes.isEmpty
                    || summary.fieldsTransformed > 0
            }
            .prefix(limit)
            .map { $0 }
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

    // MARK: - Internals

    private static func parseLine(_ line: String) -> Entry? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = object["kind"] as? String,
              let server = object["server"] as? String,
              let tool = object["tool"] as? String,
              let code = object["code"] as? String else {
            return nil
        }
        let types = (object["secretTypes"] as? [String]) ?? []
        let fields = (object["fieldsTransformed"] as? Int)
            ?? (object["fieldsTransformed"] as? NSNumber)?.intValue
            ?? 0
        return Entry(
            kind: kind,
            server: server,
            tool: tool,
            code: code,
            secretTypes: types,
            fieldsTransformed: fields
        )
    }

    private static func sanitize(_ text: String) -> String {
        let trimmed = String(text.prefix(120))
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return trimmed }
        return trimmed.replacingOccurrences(of: home, with: "~")
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

/// Helpers for MCP rule ergonomics in show/doctor.
public enum OffsendMCPRuleAdvice {
    /// High-risk inventory servers with no matching `context.mcp.rules` entry.
    public static func uncoveredHighRiskServers(
        servers: [ShowMCPServer],
        rules: [OffsendMCPRule]?
    ) -> [String] {
        let ruleList = rules ?? []
        return servers
            .filter(\.highRisk)
            .map(\.name)
            .filter { server in
                !ruleList.contains { ruleCovers(server: server, rule: $0) }
            }
            .sorted()
    }

    /// Activity hits that look sensitive and have no tool-specific rule.
    public static func uncoveredActivityHits(
        hits: [MCPActivityLog.HitSummary],
        rules: [OffsendMCPRule]?
    ) -> [MCPActivityLog.HitSummary] {
        let ruleList = rules ?? []
        return hits.filter { hit in
            let interesting = hit.lastCode.contains("secret")
                || hit.lastCode.contains("sealed")
                || hit.fieldsTransformed > 0
                || !hit.secretTypes.isEmpty
            guard interesting else { return false }
            return !ruleList.contains { ruleCovers(server: hit.server, tool: hit.tool, rule: $0) }
        }
    }

    /// True when some rule declares `fields` but that rule's effective responses
    /// mode is not `seal` (fields seal/drop never run).
    public static func hasFieldsWithoutSealResponses(
        rules: [OffsendMCPRule]?,
        globalResponses: String?
    ) -> Bool {
        (rules ?? []).contains { rule in
            guard !(rule.fields ?? [:]).isEmpty else { return false }
            if rule.responses == "seal" { return false }
            if rule.responses == nil, globalResponses == "seal" { return false }
            return true
        }
    }

    /// True when the rule explicitly targets this server (not tool-only / `*`).
    /// Tool-only rules must not silence "high-risk server without rules" advice.
    public static func ruleCovers(server: String, rule: OffsendMCPRule) -> Bool {
        let pattern = rule.match.server?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pattern, !pattern.isEmpty, pattern != "*" else { return false }
        return OffsendMCPInventory.matchesNamePattern(pattern, value: server)
    }

    public static func ruleCovers(server: String, tool: String, rule: OffsendMCPRule) -> Bool {
        OffsendMCPRuleResolver.specificity(rule.match, server: server, tool: tool) != nil
    }

    public static func summarizeRule(_ rule: OffsendMCPRule) -> String {
        let server = rule.match.server ?? "*"
        let tool = rule.match.tool ?? "*"
        var bits: [String] = []
        if let mode = rule.mode, !mode.isEmpty { bits.append("mode: \(mode)") }
        if let responses = rule.responses, !responses.isEmpty { bits.append("responses: \(responses)") }
        if let fields = rule.fields, !fields.isEmpty {
            let fieldBits = fields.keys.sorted().prefix(4).map { key in
                "\(key)=\(fields[key] ?? "")"
            }
            var fieldSummary = "fields: \(fieldBits.joined(separator: ", "))"
            if fields.count > 4 { fieldSummary += ", …" }
            bits.append(fieldSummary)
        }
        let detail = bits.isEmpty ? "(no overrides)" : bits.joined(separator: "; ")
        return "\(server)/\(tool) → \(detail)"
    }
}
