import Foundation

/// AI-context controls beyond ignore files: MCP policy, subagents, history hygiene.
public struct OffsendProjectContextConfig: Codable, Equatable, Sendable {
    public var mcp: OffsendProjectMCPConfig?
    public var subagents: OffsendProjectSubagentsConfig?
    public var history: OffsendProjectHistoryConfig?

    public init(
        mcp: OffsendProjectMCPConfig? = nil,
        subagents: OffsendProjectSubagentsConfig? = nil,
        history: OffsendProjectHistoryConfig? = nil
    ) {
        self.mcp = mcp
        self.subagents = subagents
        self.history = history
    }
}

public struct OffsendProjectMCPConfig: Codable, Equatable, Sendable {
    /// `observe` (report only), `ask` (confirm), or `deny` (block).
    public var mode: String?
    public var allow: [String]?
    public var deny: [String]?
    /// Glob-ish server name patterns flagged as high-risk in show/doctor.
    public var highRisk: [String]?

    enum CodingKeys: String, CodingKey {
        case mode
        case allow
        case deny
        case highRisk = "high_risk"
    }

    public init(
        mode: String? = nil,
        allow: [String]? = nil,
        deny: [String]? = nil,
        highRisk: [String]? = nil
    ) {
        self.mode = mode
        self.allow = allow
        self.deny = deny
        self.highRisk = highRisk
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

    enum CodingKeys: String, CodingKey {
        case audit
        case scrubOnProtect = "scrub_on_protect"
    }

    public init(audit: Bool? = nil, scrubOnProtect: Bool? = nil) {
        self.audit = audit
        self.scrubOnProtect = scrubOnProtect
    }
}

public enum OffsendContextEnforcementMode: String, CaseIterable, Sendable {
    case observe
    case ask
    case deny
}
