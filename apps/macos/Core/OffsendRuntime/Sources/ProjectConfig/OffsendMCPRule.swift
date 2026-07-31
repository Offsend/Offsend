import Foundation

/// `context.mcp.rules[].match` — optional server/tool globs (`*` wildcards).
/// Omit a side (or use `"*"`) to match any value on that side. At least one of
/// `server` / `tool` must be set for the rule to be valid.
public struct OffsendMCPRuleMatch: Codable, Equatable, Sendable {
    public var server: String?
    public var tool: String?

    public init(server: String? = nil, tool: String? = nil) {
        self.server = server
        self.tool = tool
    }
}

/// Field action under `context.mcp.rules[].fields`.
public enum OffsendMCPFieldAction: String, CaseIterable, Sendable {
    /// Replace the scalar (or leaf scalars under a container) with seal tokens.
    case seal
    /// Keep the key, set the value to JSON `null`.
    case drop
    /// Do not apply field sealing/drop to this path; detector floor still applies.
    case pass
}

/// Per-tool override under `context.mcp.rules`.
/// Unset `mode` / `responses` fall back to the global `context.mcp` values.
public struct OffsendMCPRule: Codable, Equatable, Sendable {
    public var match: OffsendMCPRuleMatch
    public var mode: String?
    public var responses: String?
    /// JSON path patterns → `seal` | `drop` | `pass`. Applied in `responses: seal`
    /// when the tool output is a JSON object/array. Bare key names match at any depth.
    public var fields: [String: String]?

    public init(
        match: OffsendMCPRuleMatch,
        mode: String? = nil,
        responses: String? = nil,
        fields: [String: String]? = nil
    ) {
        self.match = match
        self.mode = mode
        self.responses = responses
        self.fields = fields
    }
}

/// Resolves the most specific matching `context.mcp.rules` entry for a call.
public enum OffsendMCPRuleResolver {
    /// Most specific matching rule, or `nil` when none match.
    /// On equal specificity, the earlier list entry wins.
    public static func matchingRule(
        in config: OffsendProjectMCPConfig?,
        server: String,
        tool: String
    ) -> OffsendMCPRule? {
        guard let rules = config?.rules, !rules.isEmpty else { return nil }
        var best: (rule: OffsendMCPRule, score: Int, index: Int)?
        for (index, rule) in rules.enumerated() {
            guard let score = specificity(rule.match, server: server, tool: tool) else { continue }
            if let current = best {
                if score > current.score || (score == current.score && index < current.index) {
                    best = (rule, score, index)
                }
            } else {
                best = (rule, score, index)
            }
        }
        return best?.rule
    }

    public static func effectiveMode(
        mcpConfig: OffsendProjectMCPConfig?,
        server: String,
        tool: String
    ) -> OffsendContextEnforcementMode {
        if let raw = matchingRule(in: mcpConfig, server: server, tool: tool)?.mode,
           let mode = OffsendContextEnforcementMode(rawValue: raw) {
            return mode
        }
        return OffsendContextEnforcementMode(rawValue: mcpConfig?.mode ?? "") ?? .ask
    }

    public static func effectiveResponseMode(
        mcpConfig: OffsendProjectMCPConfig?,
        server: String,
        tool: String
    ) -> OffsendMCPResponseMode {
        if let raw = matchingRule(in: mcpConfig, server: server, tool: tool)?.responses,
           let mode = OffsendMCPResponseMode(rawValue: raw) {
            return mode
        }
        return OffsendMCPResponseMode(rawValue: mcpConfig?.responses ?? "") ?? .observe
    }

    /// Parsed field actions from all matching rules (invalid actions skipped).
    /// More specific matches override the same path; on equal specificity the
    /// earlier list entry wins. A narrow rule without `fields` no longer drops
    /// fields inherited from a broader matching rule.
    public static func effectiveFieldActions(
        mcpConfig: OffsendProjectMCPConfig?,
        server: String,
        tool: String
    ) -> [String: OffsendMCPFieldAction] {
        guard let rules = mcpConfig?.rules, !rules.isEmpty else { return [:] }

        var matched: [(score: Int, index: Int, fields: [String: String])] = []
        for (index, rule) in rules.enumerated() {
            guard let score = specificity(rule.match, server: server, tool: tool),
                  let fields = rule.fields, !fields.isEmpty else { continue }
            matched.append((score, index, fields))
        }
        guard !matched.isEmpty else { return [:] }

        // Apply broad → specific so later writes win. On equal score, earlier
        // list index wins (apply higher index first, then lower).
        matched.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.index > rhs.index
        }

        var parsed: [String: OffsendMCPFieldAction] = [:]
        for item in matched {
            for (pattern, raw) in item.fields {
                let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty,
                      let action = OffsendMCPFieldAction(
                        rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)
                      )
                else { continue }
                parsed[key] = action
            }
        }
        return parsed
    }

    /// Score for a matching rule; `nil` when the rule does not apply.
    /// Exact > glob-with-`*` > `*` / omitted. Server weight is higher so
    /// `server: postgres, tool: *` beats `server: *, tool: query`.
    static func specificity(
        _ match: OffsendMCPRuleMatch,
        server: String,
        tool: String
    ) -> Int? {
        let serverPattern = normalizedPattern(match.server)
        let toolPattern = normalizedPattern(match.tool)
        guard OffsendMCPInventory.matchesNamePattern(serverPattern, value: server),
              OffsendMCPInventory.matchesNamePattern(toolPattern, value: tool) else {
            return nil
        }
        return patternScore(serverPattern) * 4 + patternScore(toolPattern)
    }

    private static func normalizedPattern(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "*" }
        return value
    }

    private static func patternScore(_ pattern: String) -> Int {
        if pattern == "*" { return 0 }
        if pattern.contains("*") { return 1 }
        return 2
    }
}
