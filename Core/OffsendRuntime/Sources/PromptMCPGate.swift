import DetectionCore
import Foundation

public enum PromptMCPGatePermission: String, Equatable, Sendable {
    case allow
    case ask
    case deny
}

public struct PromptMCPGateCall: Equatable, Sendable {
    public let server: String
    public let tool: String
    /// Serialized tool arguments (JSON string or flattened text).
    public let toolInput: String
    public let cwd: String?

    public init(server: String, tool: String, toolInput: String, cwd: String? = nil) {
        self.server = server
        self.tool = tool
        self.toolInput = toolInput
        self.cwd = cwd
    }
}

public struct PromptMCPGateDecision: Equatable, Sendable {
    public let call: PromptMCPGateCall
    public let permission: PromptMCPGatePermission
    public let reason: String
    /// Short machine code: `allow`, `policy`, `sensitive_path`, `secrets`.
    public let code: String
    public let suspiciousPaths: [String]
    public let secretTypes: [String]

    public var allowed: Bool { permission == .allow }

    public init(
        call: PromptMCPGateCall,
        permission: PromptMCPGatePermission,
        reason: String,
        code: String,
        suspiciousPaths: [String] = [],
        secretTypes: [String] = []
    ) {
        self.call = call
        self.permission = permission
        self.reason = reason
        self.code = code
        self.suspiciousPaths = suspiciousPaths
        self.secretTypes = secretTypes
    }
}

/// Best-effort gate for Cursor `beforeMCPExecution` / Claude `PreToolUse` (MCP tools).
/// Enforces optional allow/deny lists, sensitive-path tokens in tool args, and secret-shaped values.
public enum PromptMCPGate {
    public static func parse(json: String, adapter: CheckHookAdapter) throws -> PromptMCPGateCall {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        guard let call = extractCall(from: root, adapter: adapter) else {
            throw PromptHookInputError.invalidJSON
        }
        return call
    }

    public static func evaluate(
        call: PromptMCPGateCall,
        mcpConfig: OffsendProjectMCPConfig? = nil,
        secretTypes: [String] = []
    ) -> PromptMCPGateDecision {
        let mode = OffsendContextEnforcementMode(rawValue: mcpConfig?.mode ?? "") ?? .ask

        if let policy = evaluatePolicy(server: call.server, mcpConfig: mcpConfig) {
            let permission = permission(for: mode, finding: true)
            return PromptMCPGateDecision(
                call: call,
                permission: permission,
                reason: policy.reason,
                code: "policy",
                suspiciousPaths: [],
                secretTypes: []
            )
        }

        let paths = suspiciousPaths(in: call.toolInput, cwd: call.cwd)
        if !paths.isEmpty {
            let names = paths.joined(separator: ", ")
            let permission = permission(for: mode, finding: true)
            return PromptMCPGateDecision(
                call: call,
                permission: permission,
                reason: "Offsend: MCP tool args reference sensitive path (\(names)) — "
                    + "secrets can fuel further tool use.",
                code: "sensitive_path",
                suspiciousPaths: paths,
                secretTypes: []
            )
        }

        if !secretTypes.isEmpty {
            let typeList = secretTypes.joined(separator: ", ")
            let permission = permission(for: mode, finding: true)
            return PromptMCPGateDecision(
                call: call,
                permission: permission,
                reason: "Offsend: MCP tool args contain secrets (\(typeList)) — "
                    + "keep credentials out of agent context.",
                code: "secrets",
                suspiciousPaths: [],
                secretTypes: secretTypes
            )
        }

        return PromptMCPGateDecision(
            call: call,
            permission: .allow,
            reason: "",
            code: "allow"
        )
    }

    public static func extractCall(from root: [String: Any], adapter: CheckHookAdapter) -> PromptMCPGateCall? {
        switch adapter {
        case .cursor:
            return extractCursorCall(from: root)
        case .claude:
            return extractClaudeCall(from: root)
        case .windsurf, .codex:
            return nil
        }
    }

    /// Claude MCP tools are named `mcp__<server>__<tool>`.
    public static func isClaudeMCPToolName(_ toolName: String) -> Bool {
        toolName.hasPrefix("mcp__")
    }

    public static func parseClaudeMCPToolName(_ toolName: String) -> (server: String, tool: String)? {
        guard isClaudeMCPToolName(toolName) else { return nil }
        // `mcp__server__tool` → drop prefix, then split on `__`.
        let rest = String(toolName.dropFirst("mcp__".count))
        let segments = rest.split(separator: "__", maxSplits: 1, omittingEmptySubsequences: false)
        guard segments.count == 2 else {
            return (server: rest.isEmpty ? "unknown" : rest, tool: toolName)
        }
        let server = String(segments[0])
        let tool = String(segments[1])
        return (server: server.isEmpty ? "unknown" : server, tool: tool.isEmpty ? toolName : tool)
    }

    // MARK: - Policy

    private struct PolicyHit {
        let reason: String
    }

    private static func evaluatePolicy(
        server: String,
        mcpConfig: OffsendProjectMCPConfig?
    ) -> PolicyHit? {
        guard let mcpConfig else { return nil }
        let allow = mcpConfig.allow ?? []
        let deny = mcpConfig.deny ?? []
        guard !allow.isEmpty || !deny.isEmpty else { return nil }

        let serverLower = server.lowercased()
        let denyPatterns = deny.filter { $0 != "*" }
        if matchesAny(denyPatterns, value: serverLower) {
            return PolicyHit(reason: "Offsend: MCP server '\(server)' is denied by context.mcp.deny.")
        }

        // Allowlist mode: a non-empty `allow` (or `deny: ["*"]`) restricts servers to the allow list.
        if !allow.isEmpty || deny.contains("*") {
            if !matchesAny(allow, value: serverLower) {
                return PolicyHit(reason: "Offsend: MCP server '\(server)' is not in context.mcp.allow.")
            }
        }
        return nil
    }

    private static func matchesAny(_ patterns: [String], value: String) -> Bool {
        guard !patterns.isEmpty else { return false }
        return OffsendMCPInventory.isHighRisk(name: value, patterns: patterns.map { $0.lowercased() })
    }

    private static func permission(
        for mode: OffsendContextEnforcementMode,
        finding: Bool
    ) -> PromptMCPGatePermission {
        guard finding else { return .allow }
        switch mode {
        case .observe: return .allow
        case .ask: return .ask
        case .deny: return .deny
        }
    }

    // MARK: - Extraction

    private static func extractCursorCall(from root: [String: Any]) -> PromptMCPGateCall? {
        let tool = nonEmptyString(root["tool_name"])
            ?? nonEmptyString(root["toolName"])
            ?? ""
        // Cursor may put the config key in `command` (known quirk) or a real `server` field.
        let server = nonEmptyString(root["server"])
            ?? nonEmptyString(root["command"])
            ?? "unknown"
        guard !tool.isEmpty || server != "unknown" else { return nil }
        let toolInput = stringifyToolInput(root["tool_input"] ?? root["toolInput"])
        let cwd = nonEmptyString(root["cwd"])
            ?? (root["workspace_roots"] as? [String])?.first
        return PromptMCPGateCall(
            server: server,
            tool: tool.isEmpty ? "unknown" : tool,
            toolInput: toolInput,
            cwd: cwd
        )
    }

    private static func extractClaudeCall(from root: [String: Any]) -> PromptMCPGateCall? {
        let toolName = nonEmptyString(root["tool_name"])
            ?? nonEmptyString(root["toolName"])
            ?? ""
        guard let parsed = parseClaudeMCPToolName(toolName) else { return nil }
        let toolInput = stringifyToolInput(root["tool_input"] ?? root["toolInput"])
        let cwd = nonEmptyString(root["cwd"])
        return PromptMCPGateCall(
            server: parsed.server,
            tool: parsed.tool,
            toolInput: toolInput,
            cwd: cwd
        )
    }

    private static func stringifyToolInput(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if let object = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let array = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    // MARK: - Path heuristics

    private static func suspiciousPaths(in toolInput: String, cwd: String?) -> [String] {
        var seen = Set<String>()
        var suspicious: [String] = []
        for candidate in PromptShellGate.pathCandidates(in: toolInput) {
            var paths = [candidate]
            for resolved in PromptReadGate.sensitivityCheckPaths(for: candidate, cwd: cwd)
                where !paths.contains(resolved) {
                paths.append(resolved)
            }
            for path in paths where PromptAttachmentAdvisor.isSuspicious(path: path) {
                let name = URL(fileURLWithPath: path).lastPathComponent
                if seen.insert(name.lowercased()).inserted {
                    suspicious.append(name)
                }
                break
            }
        }
        // Also scan JSON string values that look like paths (quoted).
        for match in toolInput.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "_" && $0 != "-" && $0 != "/" && $0 != "~" }) {
            let token = String(match)
            guard token.contains("/") || token.hasPrefix(".") || token.hasPrefix("~") else { continue }
            if let name = firstSuspiciousBasename(token, cwd: cwd),
               seen.insert(name.lowercased()).inserted {
                suspicious.append(name)
            }
        }
        return suspicious
    }

    private static func firstSuspiciousBasename(_ candidate: String, cwd: String?) -> String? {
        var paths = [candidate]
        for resolved in PromptReadGate.sensitivityCheckPaths(for: candidate, cwd: cwd)
            where !paths.contains(resolved) {
            paths.append(resolved)
        }
        for path in paths where PromptAttachmentAdvisor.isSuspicious(path: path) {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return nil
    }
}

public enum PromptMCPGateRenderer {
    public static func render(
        decision: PromptMCPGateDecision,
        adapter: CheckHookAdapter
    ) -> CheckHookAdapterOutput {
        switch adapter {
        case .cursor:
            return renderCursor(decision)
        case .claude:
            return renderClaude(decision)
        case .windsurf, .codex:
            return CheckHookAdapterOutput(stdout: "", stderr: "", exitCode: 0)
        }
    }

    private static func renderCursor(_ decision: PromptMCPGateDecision) -> CheckHookAdapterOutput {
        switch decision.permission {
        case .allow:
            var stderr = ""
            if decision.code != "allow", !decision.reason.isEmpty {
                // observe mode: surface the finding without blocking
                stderr = decision.reason + "\n"
            }
            return CheckHookAdapterOutput(
                stdout: jsonObject(["permission": "allow"]),
                stderr: stderr,
                exitCode: 0
            )
        case .ask:
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "permission": "ask",
                    "user_message": decision.reason,
                    "agent_message": agentMessage(for: decision),
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        case .deny:
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "permission": "deny",
                    "user_message": decision.reason,
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        }
    }

    private static func renderClaude(_ decision: PromptMCPGateDecision) -> CheckHookAdapterOutput {
        switch decision.permission {
        case .allow:
            var stderr = ""
            if decision.code != "allow", !decision.reason.isEmpty {
                stderr = decision.reason + "\n"
            }
            return CheckHookAdapterOutput(stdout: "{}", stderr: stderr, exitCode: 0)
        case .ask, .deny:
            let permission = decision.permission == .ask ? "ask" : "deny"
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "hookSpecificOutput": [
                        "hookEventName": "PreToolUse",
                        "permissionDecision": permission,
                        "permissionDecisionReason": decision.reason,
                    ],
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        }
    }

    private static func agentMessage(for decision: PromptMCPGateDecision) -> String {
        switch decision.code {
        case "policy":
            return "This MCP server is restricted by project policy (context.mcp). Ask the user before continuing, or update .offsend.yml."
        case "sensitive_path":
            return "MCP args reference sensitive files (\(decision.suspiciousPaths.joined(separator: ", "))). Prefer env vars / AI ignore files."
        case "secrets":
            return "MCP args appear to contain secrets (\(decision.secretTypes.joined(separator: ", "))). Do not send secret material through tools."
        default:
            return decision.reason
        }
    }

    private static func jsonObject(_ object: [String: Any]) -> String {
        CheckHookResponseRenderer.encodeJSONObject(object)
    }
}
