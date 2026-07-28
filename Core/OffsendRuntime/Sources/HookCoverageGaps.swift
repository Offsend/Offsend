import Foundation

/// Residual AI-hook coverage gaps. Offsend is not a sandbox — these paths stay
/// outside gate enforcement even when hooks are installed correctly.
public enum HookCoverageGap: String, CaseIterable, Sendable {
    case mcpResponses = "MCP response payloads"
    case claudeSubagents = "Claude subagents"
    case cursorOpenTabs = "Cursor open tabs"
    /// Cursor can rewrite MCP `postToolUse` output only; Grep match bodies stay plaintext
    /// unless seal mode denies Grep via `--grep-gate`.
    case cursorGrepSearch = "Cursor Grep/search plaintext"
    case cloudSessions = "cloud agent sessions"

    /// Gaps relevant for the current editor/MCP surface. `cloudSessions` always
    /// applies when any AI hook is installed (cannot be detected locally).
    ///
    /// An MCP response gap closes only when the installed target is actively
    /// replacing and sealing responses, not merely observing them.
    public static func active(
        cursorInstalled: Bool,
        claudeInstalled: Bool,
        mcpSurfaceActive: Bool,
        mcpResponseProtectedCursor: Bool = false,
        mcpResponseProtectedClaude: Bool = false,
        cursorGrepGateInstalled: Bool = false,
        readSealMode: Bool = false
    ) -> [HookCoverageGap] {
        var gaps: [HookCoverageGap] = []
        if mcpSurfaceActive {
            let cursorCovered = !cursorInstalled || mcpResponseProtectedCursor
            let claudeCovered = !claudeInstalled || mcpResponseProtectedClaude
            if !cursorCovered || !claudeCovered {
                gaps.append(.mcpResponses)
            }
        }
        if claudeInstalled {
            gaps.append(.claudeSubagents)
        }
        if cursorInstalled {
            gaps.append(.cursorOpenTabs)
            // Seal mode + grep-gate closes the Grep plaintext channel by denying Grep.
            // Without seal (or without the gate), workspace Grep can still return secrets.
            if !(readSealMode && cursorGrepGateInstalled) {
                gaps.append(.cursorGrepSearch)
            }
        }
        gaps.append(.cloudSessions)
        return gaps
    }

    public static func doctorMessage(for gaps: [HookCoverageGap]) -> String {
        let list = gaps.map(\.rawValue).joined(separator: "; ")
        return "Residual hook gaps (not a sandbox): \(list). "
            + "Prefer protect/ignore. See docs/cli.md#what-hooks-do-not-cover"
    }

    /// Gaps that warrant a doctor **warn** (editor/MCP surface). `cloudSessions` alone
    /// stays informational (`.ok`) — every local install has that residual limit.
    public static func hasActionableGaps(_ gaps: [HookCoverageGap]) -> Bool {
        gaps.contains { $0 != .cloudSessions }
    }
}

enum MCPResponseProtection {
    static func isActive(
        hookInstalled: Bool,
        replacementEventInstalled: Bool,
        wrapperHealthy: Bool,
        configuredMode: String?,
        sealKeyAvailable: Bool
    ) -> Bool {
        hookInstalled
            && replacementEventInstalled
            && wrapperHealthy
            && configuredMode == OffsendMCPResponseMode.seal.rawValue
            && sealKeyAvailable
    }
}
