import Foundation

/// Residual AI-hook coverage gaps. Offsend is not a sandbox — these paths stay
/// outside gate enforcement even when hooks are installed correctly.
public enum HookCoverageGap: String, CaseIterable, Sendable {
    case mcpResponses = "MCP response payloads"
    case claudeSubagents = "Claude subagents"
    case cursorOpenTabs = "Cursor open tabs"
    case cloudSessions = "cloud agent sessions"

    /// Gaps relevant for the current editor/MCP surface. `cloudSessions` always
    /// applies when any AI hook is installed (cannot be detected locally).
    ///
    /// `mcpResponseGateClaude` narrows `mcpResponses`: Claude `PostToolUse` can
    /// rewrite MCP output, so an installed response gate closes the gap there.
    /// Cursor `afterMCPExecution` is observe-only — with Cursor installed the
    /// gap stays even when the response gate is on.
    public static func active(
        cursorInstalled: Bool,
        claudeInstalled: Bool,
        mcpSurfaceActive: Bool,
        mcpResponseGateClaude: Bool = false
    ) -> [HookCoverageGap] {
        var gaps: [HookCoverageGap] = []
        if mcpSurfaceActive {
            let claudeCovered = !claudeInstalled || mcpResponseGateClaude
            if cursorInstalled || !claudeCovered {
                gaps.append(.mcpResponses)
            }
        }
        if claudeInstalled {
            gaps.append(.claudeSubagents)
        }
        if cursorInstalled {
            gaps.append(.cursorOpenTabs)
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
