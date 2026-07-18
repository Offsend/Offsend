import Foundation

public struct OffsendMCPServer: Equatable, Sendable {
    public let name: String
    /// Where the server was declared (`cursor-project`, `cursor-user`, `claude-project`, …).
    public let source: String
    /// Short transport summary (command line or URL), never secret values.
    public let detail: String
    public let highRisk: Bool

    public init(name: String, source: String, detail: String, highRisk: Bool) {
        self.name = name
        self.source = source
        self.detail = detail
        self.highRisk = highRisk
    }
}

public struct OffsendMCPInventoryReport: Equatable, Sendable {
    public let servers: [OffsendMCPServer]
    public let policyMode: String?
    public let hasAllowlist: Bool
    public let hasDenylist: Bool

    public init(
        servers: [OffsendMCPServer],
        policyMode: String?,
        hasAllowlist: Bool,
        hasDenylist: Bool
    ) {
        self.servers = servers
        self.policyMode = policyMode
        self.hasAllowlist = hasAllowlist
        self.hasDenylist = hasDenylist
    }

    public var isEmpty: Bool { servers.isEmpty }
}

/// Discovers MCP server declarations from Cursor / Claude config files.
public struct OffsendMCPInventory: Sendable {
    public static let defaultHighRiskPatterns: [String] = [
        "filesystem",
        "postgres",
        "postgresql",
        "sqlite",
        "mysql",
        "mongodb",
        "mongo",
        "redis",
        "aws",
        "gdrive",
        "google-drive",
        "db-*",
        "*-db",
        "sql*",
    ]

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func collect(
        projectRoot: URL,
        homeDirectory: URL,
        mcpConfig: OffsendProjectMCPConfig? = nil
    ) -> OffsendMCPInventoryReport {
        let highRisk = (mcpConfig?.highRisk?.isEmpty == false)
            ? (mcpConfig?.highRisk ?? [])
            : Self.defaultHighRiskPatterns

        var servers: [OffsendMCPServer] = []
        servers.append(contentsOf: loadServers(
            at: projectRoot.appendingPathComponent(".cursor/mcp.json"),
            source: "cursor-project",
            highRiskPatterns: highRisk
        ))
        servers.append(contentsOf: loadServers(
            at: homeDirectory.appendingPathComponent(".cursor/mcp.json"),
            source: "cursor-user",
            highRiskPatterns: highRisk
        ))
        servers.append(contentsOf: loadServers(
            at: projectRoot.appendingPathComponent(".mcp.json"),
            source: "claude-project",
            highRiskPatterns: highRisk
        ))
        servers.append(contentsOf: loadServers(
            fromSettingsJSON: projectRoot.appendingPathComponent(".claude/settings.json"),
            source: "claude-settings",
            highRiskPatterns: highRisk
        ))
        servers.append(contentsOf: loadServers(
            at: homeDirectory
                .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json"),
            source: "claude-desktop",
            highRiskPatterns: highRisk
        ))

        // Stable, de-duplicated by name+source.
        var seen = Set<String>()
        let unique = servers.filter { server in
            let key = "\(server.source)::\(server.name.lowercased())"
            return seen.insert(key).inserted
        }
        .sorted {
            if $0.highRisk != $1.highRisk { return $0.highRisk && !$1.highRisk }
            if $0.name.localizedCaseInsensitiveCompare($1.name) != .orderedSame {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.source < $1.source
        }

        return OffsendMCPInventoryReport(
            servers: unique,
            policyMode: mcpConfig?.mode,
            hasAllowlist: !(mcpConfig?.allow ?? []).isEmpty,
            hasDenylist: !(mcpConfig?.deny ?? []).isEmpty
        )
    }

    public static func isHighRisk(name: String, patterns: [String]) -> Bool {
        let lower = name.lowercased()
        for pattern in patterns {
            if matchesGlob(pattern.lowercased(), value: lower) {
                return true
            }
        }
        return false
    }

    // MARK: - Loading

    private func loadServers(
        at url: URL,
        source: String,
        highRiskPatterns: [String]
    ) -> [OffsendMCPServer] {
        guard let root = readJSONObject(at: url) else { return [] }
        return parseMCPServers(from: root, source: source, highRiskPatterns: highRiskPatterns)
    }

    private func loadServers(
        fromSettingsJSON url: URL,
        source: String,
        highRiskPatterns: [String]
    ) -> [OffsendMCPServer] {
        guard let root = readJSONObject(at: url) else { return [] }
        // Claude settings may nest under mcpServers at the top level.
        return parseMCPServers(from: root, source: source, highRiskPatterns: highRiskPatterns)
    }

    private func parseMCPServers(
        from root: [String: Any],
        source: String,
        highRiskPatterns: [String]
    ) -> [OffsendMCPServer] {
        guard let servers = root["mcpServers"] as? [String: Any] else { return [] }
        return servers.keys.sorted().compactMap { name -> OffsendMCPServer? in
            guard let entry = servers[name] else { return nil }
            let detail = summarize(entry: entry)
            return OffsendMCPServer(
                name: name,
                source: source,
                detail: detail,
                highRisk: Self.isHighRisk(name: name, patterns: highRiskPatterns)
            )
        }
    }

    private func summarize(entry: Any) -> String {
        guard let object = entry as? [String: Any] else { return "" }
        if let url = object["url"] as? String, !url.isEmpty {
            return truncate(Self.maskURLUserinfo(url))
        }
        if let command = object["command"] as? String, !command.isEmpty {
            let args = (object["args"] as? [Any] ?? []).compactMap { $0 as? String }
            let joined = ([command] + Self.maskSecretArgs(args)).joined(separator: " ")
            return truncate(joined)
        }
        if object["type"] as? String == "http" || object["type"] as? String == "sse" {
            if let url = object["url"] as? String { return truncate(Self.maskURLUserinfo(url)) }
        }
        return ""
    }

    private static let secretArgKeywords = [
        "token", "key", "secret", "password", "passwd", "auth", "credential", "bearer",
    ]

    private static func looksLikeSecretArgName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return secretArgKeywords.contains { lower.contains($0) }
    }

    /// Mask values of secret-looking flags (`--api-key sk-…`, `--token=abc`) and env-style
    /// assignments (`API_KEY="…"`) so `show`/`doctor` never print secret material from mcp.json args.
    static func maskSecretArgs(_ args: [String]) -> [String] {
        var masked: [String] = []
        var maskNext = false
        for arg in args {
            if maskNext {
                masked.append("***")
                maskNext = false
                continue
            }
            // `--token=abc` and `API_KEY="abc"` both carry the value after `=`.
            if let eq = arg.firstIndex(of: "="), eq != arg.startIndex {
                let name = String(arg[..<eq])
                if looksLikeSecretArgName(name) {
                    masked.append(name + "=***")
                    continue
                }
            }
            if arg.hasPrefix("-"), looksLikeSecretArgName(arg) {
                masked.append(arg)
                maskNext = true
                continue
            }
            masked.append(Self.maskURLUserinfo(arg))
        }
        return masked
    }

    /// Mask `scheme://user:pass@host` userinfo so credentials embedded in URLs never surface.
    static func maskURLUserinfo(_ value: String) -> String {
        guard let schemeRange = value.range(of: "://") else { return value }
        let afterScheme = schemeRange.upperBound
        let hostEnd = value[afterScheme...].firstIndex(of: "/") ?? value.endIndex
        guard let atIndex = value[afterScheme..<hostEnd].lastIndex(of: "@") else { return value }
        return value.replacingCharacters(in: afterScheme..<atIndex, with: "***")
    }

    private func truncate(_ value: String, limit: Int = 80) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "…"
    }

    private func readJSONObject(at url: URL) -> [String: Any]? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return nil
        }
        return root
    }

    /// Minimal glob: `*` matches any run of characters; otherwise exact match.
    private static func matchesGlob(_ pattern: String, value: String) -> Bool {
        if pattern == "*" { return true }
        if !pattern.contains("*") { return pattern == value }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        guard let regex = try? NSRegularExpression(pattern: "^\(escaped)$") else {
            return pattern == value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}
