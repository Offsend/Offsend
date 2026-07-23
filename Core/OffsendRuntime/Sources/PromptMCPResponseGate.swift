import DetectionCore
import Foundation

/// A parsed MCP tool **response** from Cursor `afterMCPExecution` or Claude
/// `PostToolUse` (`mcp__*` tools).
public struct PromptMCPResponseCall: Equatable, Sendable {
    public let server: String
    public let tool: String
    /// Serialized response text, bounded by `PromptMCPResponseGate.maxResponseCharacters`.
    public let responseText: String
    /// True when the raw response exceeded the scan budget and was cut.
    public let truncated: Bool

    public init(server: String, tool: String, responseText: String, truncated: Bool = false) {
        self.server = server
        self.tool = tool
        self.responseText = responseText
        self.truncated = truncated
    }
}

public struct PromptMCPResponseDecision: Equatable, Sendable {
    public let call: PromptMCPResponseCall
    public let mode: OffsendMCPResponseMode
    public let secretTypes: [String]
    /// Full replacement output with secrets sealed (`{{TYPE:v1.…}}` tokens).
    /// Only set in seal mode when the key resolved and the response was not truncated.
    public let sealedOutput: String?
    public let sealedCount: Int
    public let reason: String

    public var hasFindings: Bool { !secretTypes.isEmpty }
    public var sealed: Bool { sealedOutput != nil }

    public init(
        call: PromptMCPResponseCall,
        mode: OffsendMCPResponseMode,
        secretTypes: [String],
        sealedOutput: String? = nil,
        sealedCount: Int = 0,
        reason: String
    ) {
        self.call = call
        self.mode = mode
        self.secretTypes = secretTypes
        self.sealedOutput = sealedOutput
        self.sealedCount = sealedCount
        self.reason = reason
    }
}

/// Post-execution gate for MCP tool responses (`context.mcp.responses`).
///
/// Coverage is asymmetric by design: Claude Code `PostToolUse` can replace the
/// tool output (`hookSpecificOutput.updatedToolOutput`), so `seal` mode swaps
/// secrets for seal tokens before the model sees them. Cursor
/// `afterMCPExecution` is observe-only — findings surface via stderr and the
/// hook debug log, but the response cannot be rewritten.
public enum PromptMCPResponseGate {
    /// Scan/seal budget (matches `PromptReadGate.maxContentCharacters`).
    public static let maxResponseCharacters = PromptReadGate.maxContentCharacters

    public static func parse(json: String, adapter: CheckHookAdapter) throws -> PromptMCPResponseCall {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        guard let call = extractCall(from: root, adapter: adapter) else {
            throw PromptHookInputError.invalidJSON
        }
        return call
    }

    public static func extractCall(from root: [String: Any], adapter: CheckHookAdapter) -> PromptMCPResponseCall? {
        switch adapter {
        case .cursor:
            return extractCursorCall(from: root)
        case .claude:
            return extractClaudeCall(from: root)
        case .windsurf, .codex:
            return nil
        }
    }

    /// Assembles the decision from a completed scan (and optional seal result).
    public static func evaluate(
        call: PromptMCPResponseCall,
        mcpConfig: OffsendProjectMCPConfig? = nil,
        secretTypes: [String] = [],
        sealedOutput: String? = nil,
        sealedCount: Int = 0
    ) -> PromptMCPResponseDecision {
        let mode = OffsendMCPResponseMode(rawValue: mcpConfig?.responses ?? "") ?? .observe
        guard !secretTypes.isEmpty else {
            return PromptMCPResponseDecision(
                call: call,
                mode: mode,
                secretTypes: [],
                reason: ""
            )
        }
        let typeList = secretTypes.joined(separator: ", ")
        var reason = "Offsend: MCP response from '\(call.server)/\(call.tool)' contains secrets (\(typeList))."
        if sealedOutput != nil {
            reason += " Secrets were sealed as {{…}} tokens before reaching the agent."
        } else if mode == .seal, call.truncated {
            reason += " Response too large to seal safely — treat it as compromised context."
        } else if mode == .seal {
            reason += " Sealing unavailable (no seal key) — treat the values as exposed to the agent."
        } else {
            reason += " The values are now in agent context — rotate them if they are live."
        }
        return PromptMCPResponseDecision(
            call: call,
            mode: mode,
            secretTypes: secretTypes,
            sealedOutput: sealedOutput,
            sealedCount: sealedCount,
            reason: reason
        )
    }

    // MARK: - Extraction

    private static func extractCursorCall(from root: [String: Any]) -> PromptMCPResponseCall? {
        let tool = nonEmptyString(root["tool_name"])
            ?? nonEmptyString(root["toolName"])
            ?? ""
        // Same quirk as beforeMCPExecution: the config key may sit in `command`.
        let server = nonEmptyString(root["server"])
            ?? nonEmptyString(root["command"])
            ?? "unknown"
        guard root["result_json"] != nil || root["resultJson"] != nil || !tool.isEmpty else {
            return nil
        }
        let raw = stringify(root["result_json"] ?? root["resultJson"])
        let bounded = bounded(raw)
        return PromptMCPResponseCall(
            server: server,
            tool: tool.isEmpty ? "unknown" : tool,
            responseText: bounded.text,
            truncated: bounded.truncated
        )
    }

    private static func extractClaudeCall(from root: [String: Any]) -> PromptMCPResponseCall? {
        let toolName = nonEmptyString(root["tool_name"])
            ?? nonEmptyString(root["toolName"])
            ?? ""
        guard let parsed = PromptMCPGate.parseClaudeMCPToolName(toolName) else { return nil }
        let raw = stringify(root["tool_response"] ?? root["toolResponse"])
        let bounded = bounded(raw)
        return PromptMCPResponseCall(
            server: parsed.server,
            tool: parsed.tool,
            responseText: bounded.text,
            truncated: bounded.truncated
        )
    }

    private static func bounded(_ text: String) -> (text: String, truncated: Bool) {
        guard text.count > maxResponseCharacters else { return (text, false) }
        return (String(text.prefix(maxResponseCharacters)), true)
    }

    private static func stringify(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

public enum PromptMCPResponseGateRenderer {
    public static func render(
        decision: PromptMCPResponseDecision,
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

    /// Cursor `afterMCPExecution` cannot modify the result — observe-only.
    private static func renderCursor(_ decision: PromptMCPResponseDecision) -> CheckHookAdapterOutput {
        CheckHookAdapterOutput(
            stdout: "{}",
            stderr: decision.hasFindings ? decision.reason + "\n" : "",
            exitCode: 0
        )
    }

    private static func renderClaude(_ decision: PromptMCPResponseDecision) -> CheckHookAdapterOutput {
        guard decision.hasFindings else {
            return CheckHookAdapterOutput(stdout: "{}", stderr: "", exitCode: 0)
        }
        switch decision.mode {
        case .observe:
            return CheckHookAdapterOutput(stdout: "{}", stderr: decision.reason + "\n", exitCode: 0)
        case .warn:
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "hookSpecificOutput": [
                        "hookEventName": "PostToolUse",
                        "additionalContext": decision.reason
                            + " Do not echo, store, or reuse these values.",
                    ],
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        case .seal:
            guard let sealedOutput = decision.sealedOutput else {
                // Key missing or response truncated: fall back to a warning.
                return CheckHookAdapterOutput(
                    stdout: jsonObject([
                        "hookSpecificOutput": [
                            "hookEventName": "PostToolUse",
                            "additionalContext": decision.reason
                                + " Do not echo, store, or reuse these values.",
                        ],
                    ]),
                    stderr: decision.reason + "\n",
                    exitCode: 0
                )
            }
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "hookSpecificOutput": [
                        "hookEventName": "PostToolUse",
                        "updatedToolOutput": sealedOutput,
                        // Legacy alias kept for older Claude Code builds.
                        "updatedMCPToolOutput": sealedOutput,
                        "additionalContext": "Offsend sealed \(decision.sealedCount) secret value(s) "
                            + "in this MCP response as {{TYPE:v1.…}} tokens. Keep tokens verbatim; "
                            + "the user can restore outputs with `offsend unseal`.",
                    ],
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        }
    }

    private static func jsonObject(_ object: [String: Any]) -> String {
        CheckHookResponseRenderer.encodeJSONObject(object)
    }
}
