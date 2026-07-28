import Foundation

/// Project policy lives in a workspace file an agent can rewrite, so until the
/// user runs `offsend policy trust` the gates honor only the fields that cannot
/// make a gate more permissive than its built-in default.
///
/// This is what makes deleting the trust snapshot pointless: without a snapshot
/// the live policy is read through this filter, so a rewritten `.offsend.yml`
/// can tighten gates but never loosen them.
public enum OffsendPolicyTrustFilter {
    public static func hardened(_ config: OffsendProjectConfig?) -> OffsendProjectConfig? {
        guard var config else { return nil }
        config.check = hardened(check: config.check)
        config.context = hardened(context: config.context)
        config.sandbox = hardened(sandbox: config.sandbox)
        return config
    }

    /// `enabled: true` only tightens, so it survives. Everything that could widen
    /// what a sandboxed command reaches is dropped: an agent that can rewrite
    /// `.offsend.yml` must not be able to switch off its own sandbox, and must not
    /// be able to append the endpoint it wants to exfiltrate to.
    private static func hardened(
        sandbox: OffsendProjectSandboxConfig?
    ) -> OffsendProjectSandboxConfig? {
        guard var sandbox else { return nil }
        if sandbox.enabled != true {
            sandbox.enabled = nil
        }
        if var network = sandbox.network {
            if network.default != OffsendSandboxNetworkDefault.deny.rawValue {
                network.default = nil
            }
            network.allow = nil
            sandbox.network = network
        }
        return sandbox
    }

    private static func hardened(check: OffsendProjectCheckConfig?) -> OffsendProjectCheckConfig? {
        guard var check else { return nil }
        // Both narrow what the gates look at; the default is to look at everything.
        check.exclude = nil
        check.detectors = nil
        return check
    }

    private static func hardened(
        context: OffsendProjectContextConfig?
    ) -> OffsendProjectContextConfig? {
        guard var context else { return nil }
        context.mcp = hardened(mcp: context.mcp)
        context.subagents = hardened(subagents: context.subagents)
        context.shell = hardened(shell: context.shell)
        // `context.read.on_secret` is deliberately not filtered. `seal` still
        // denies the read and keeps detected secrets out of context; it only
        // hands over the non-secret remainder of a blocked file. Neutralizing it
        // would disable seal-for-agents for everyone who has not run
        // `offsend policy trust`, which is a worse trade than that residual.
        return context
    }

    private static func hardened(shell: OffsendProjectShellConfig?) -> OffsendProjectShellConfig? {
        guard var shell else { return nil }
        // Default is deny; ask would loosen the gate until the policy is trusted.
        if shell.mode != OffsendShellGateMode.deny.rawValue {
            shell.mode = nil
        }
        return shell
    }

    private static func hardened(mcp: OffsendProjectMCPConfig?) -> OffsendProjectMCPConfig? {
        guard var mcp else { return nil }
        mcp.mode = atLeastAsStrict(mcp.mode, as: .ask)
        mcp.rules = mcp.rules?.map { rule in
            var rule = rule
            rule.mode = atLeastAsStrict(rule.mode, as: .ask)
            return rule
        }
        return mcp
    }

    private static func hardened(
        subagents: OffsendProjectSubagentsConfig?
    ) -> OffsendProjectSubagentsConfig? {
        guard var subagents else { return nil }
        subagents.mode = atLeastAsStrict(subagents.mode, as: .deny)
        if subagents.scanTask == false {
            subagents.scanTask = nil
        }
        return subagents
    }

    /// Keeps the configured mode only when it is at least as strict as the
    /// built-in default; otherwise drops it so the default (or, for a rule, the
    /// already-hardened global) applies.
    private static func atLeastAsStrict(
        _ raw: String?,
        as minimum: OffsendContextEnforcementMode
    ) -> String? {
        guard let raw, let mode = OffsendContextEnforcementMode(rawValue: raw) else { return nil }
        return strictness(mode) >= strictness(minimum) ? raw : nil
    }

    private static func strictness(_ mode: OffsendContextEnforcementMode) -> Int {
        switch mode {
        case .observe: return 0
        case .ask: return 1
        case .deny: return 2
        }
    }
}
