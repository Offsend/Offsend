import Foundation

/// AI-context controls beyond ignore files: MCP policy, subagents, history hygiene, read gate.
public struct OffsendProjectContextConfig: Codable, Equatable, Sendable {
    public var mcp: OffsendProjectMCPConfig?
    public var subagents: OffsendProjectSubagentsConfig?
    public var history: OffsendProjectHistoryConfig?
    public var read: OffsendProjectReadConfig?

    public init(
        mcp: OffsendProjectMCPConfig? = nil,
        subagents: OffsendProjectSubagentsConfig? = nil,
        history: OffsendProjectHistoryConfig? = nil,
        read: OffsendProjectReadConfig? = nil
    ) {
        self.mcp = mcp
        self.subagents = subagents
        self.history = history
        self.read = read
    }
}

public struct OffsendProjectMCPConfig: Codable, Equatable, Sendable {
    /// `observe` (report only), `ask` (confirm), or `deny` (block).
    public var mode: String?
    public var allow: [String]?
    public var deny: [String]?
    /// Glob-ish server name patterns flagged as high-risk in show/doctor.
    public var highRisk: [String]?
    /// MCP **response** handling: `observe` (stderr only), `warn` (agent context note),
    /// or `seal` (Claude: replace secrets with seal tokens; Cursor: observe-only surface).
    public var responses: String?

    enum CodingKeys: String, CodingKey {
        case mode
        case allow
        case deny
        case highRisk = "high_risk"
        case responses
    }

    public init(
        mode: String? = nil,
        allow: [String]? = nil,
        deny: [String]? = nil,
        highRisk: [String]? = nil,
        responses: String? = nil
    ) {
        self.mode = mode
        self.allow = allow
        self.deny = deny
        self.highRisk = highRisk
        self.responses = responses
    }
}

/// Read-gate behavior on secret findings.
public struct OffsendProjectReadConfig: Codable, Equatable, Sendable {
    /// `block` (default: deny the read) or `seal` (deny, but hand the agent a
    /// sealed copy where secret values are replaced with `{{TYPE:v1.…}}` tokens).
    public var onSecret: String?

    enum CodingKeys: String, CodingKey {
        case onSecret = "on_secret"
    }

    public init(onSecret: String? = nil) {
        self.onSecret = onSecret
    }
}

public struct OffsendProjectSubagentsConfig: Codable, Equatable, Sendable {
    public var mode: String?
    public var scanTask: Bool?

    enum CodingKeys: String, CodingKey {
        case mode
        case scanTask = "scan_task"
    }

    public init(mode: String? = nil, scanTask: Bool? = nil) {
        self.mode = mode
        self.scanTask = scanTask
    }
}

public struct OffsendProjectHistoryConfig: Codable, Equatable, Sendable {
    public var audit: Bool?
    public var scrubOnProtect: Bool?
    /// When `true`, `offsend show` / `doctor` content-scan local transcripts (slower).
    /// Default / unset: count files only; use `offsend history audit` or `show --scan-history`.
    public var scanInShow: Bool?

    enum CodingKeys: String, CodingKey {
        case audit
        case scrubOnProtect = "scrub_on_protect"
        case scanInShow = "scan_in_show"
    }

    public init(audit: Bool? = nil, scrubOnProtect: Bool? = nil, scanInShow: Bool? = nil) {
        self.audit = audit
        self.scrubOnProtect = scrubOnProtect
        self.scanInShow = scanInShow
    }
}

public enum OffsendContextEnforcementMode: String, CaseIterable, Sendable {
    case observe
    case ask
    case deny
}

/// `context.read.on_secret` values.
public enum OffsendReadGateSecretMode: String, CaseIterable, Sendable {
    case block
    case seal
}

/// `context.mcp.responses` values.
public enum OffsendMCPResponseMode: String, CaseIterable, Sendable {
    case observe
    case warn
    case seal
}
