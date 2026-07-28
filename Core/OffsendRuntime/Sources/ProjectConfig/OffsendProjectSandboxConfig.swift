import Foundation

/// Declares that agent commands must run under an OS sandbox, and what egress
/// they may still have.
///
/// The mechanism is deliberately absent from the schema, the same way
/// `ignore.patterns` never names `.cursorignore`. Offsend picks whatever the
/// machine actually has (see `SandboxMechanismResolver`), so replacing the tool
/// later costs no migration: nobody wrote the tool's name down.
///
/// Only `network` is a portable promise. Denying *reads* exists in Claude Code
/// and nono but not in Cursor or Codex, so `enabled: true` cannot mean the same
/// filesystem guarantee everywhere — `offsend doctor` prints the position each
/// mechanism actually reached rather than the intent.
public struct OffsendProjectSandboxConfig: Codable, Equatable, Sendable {
    /// Unset is treated as `false`: a sandbox changes how every command runs, so
    /// it is opted into explicitly.
    ///
    /// `true` tightens and therefore applies without a trusted policy; `false`
    /// loosens and is ignored until `offsend policy trust`. Practical effect: an
    /// agent editing `.offsend.yml` cannot switch off its own sandbox.
    public var enabled: Bool?
    public var network: OffsendProjectSandboxNetworkConfig?

    public init(
        enabled: Bool? = nil,
        network: OffsendProjectSandboxNetworkConfig? = nil
    ) {
        self.enabled = enabled
        self.network = network
    }
}

/// Egress policy for sandboxed commands.
public struct OffsendProjectSandboxNetworkConfig: Codable, Equatable, Sendable {
    /// `deny` (default when unset) or `allow`. `allow` loosens, so it is ignored
    /// until the policy is trusted.
    public var `default`: String?
    /// Domains reachable despite `default: deny`. Each entry widens egress — the
    /// exact thing exfiltration needs — so a non-empty list is ignored until the
    /// policy is trusted. Otherwise an agent could append its own endpoint and
    /// approve its own exfil route.
    public var allow: [String]?

    public init(default defaultPolicy: String? = nil, allow: [String]? = nil) {
        self.default = defaultPolicy
        self.allow = allow
    }
}

/// `sandbox.network.default` values.
public enum OffsendSandboxNetworkDefault: String, CaseIterable, Sendable {
    case deny
    case allow

    /// Unset → `deny`: a sandbox whose egress defaults to open would not close
    /// the risk it exists for.
    public static func effective(_ raw: String?) -> OffsendSandboxNetworkDefault {
        OffsendSandboxNetworkDefault(rawValue: raw ?? "") ?? .deny
    }
}
