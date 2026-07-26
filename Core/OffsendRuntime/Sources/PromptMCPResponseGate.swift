import DetectionCore
import Foundation

public enum PromptMCPResponseShape: Equatable, Sendable {
    case string
    case object
    case array
    case scalar
}

/// A parsed MCP tool **response** from Cursor `postToolUse` (or legacy
/// `afterMCPExecution`) or Claude `PostToolUse` (`mcp__*` tools).
public struct PromptMCPResponseCall: Equatable, Sendable {
    public let server: String
    public let tool: String
    /// Serialized response text, bounded by `PromptMCPResponseGate.maxResponseBytes`.
    public let responseText: String
    /// True when the raw response exceeded the scan budget and was cut.
    public let truncated: Bool
    /// Cursor `postToolUse` can replace MCP output; legacy
    /// `afterMCPExecution` can only observe it.
    public let canReplaceOutput: Bool
    /// Original response representation, restored after sealing.
    public let responseShape: PromptMCPResponseShape

    public init(
        server: String,
        tool: String,
        responseText: String,
        truncated: Bool = false,
        canReplaceOutput: Bool = false,
        responseShape: PromptMCPResponseShape = .string
    ) {
        self.server = server
        self.tool = tool
        self.responseText = responseText
        self.truncated = truncated
        self.canReplaceOutput = canReplaceOutput
        self.responseShape = responseShape
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
    /// Keys sealed or dropped by `context.mcp.rules[].fields`.
    public let fieldsTransformed: Int
    /// Seal mode: a key resolved but sealing itself failed (e.g. a secret value
    /// over the plaintext size cap). Renderers withhold the output (fail closed)
    /// instead of downgrading to a warning.
    public let sealFailed: Bool
    public let reason: String

    public var hasFindings: Bool {
        !secretTypes.isEmpty
            || fieldsTransformed > 0
            || (mode == .seal && (call.truncated || sealFailed))
    }
    public var sealed: Bool { sealedOutput != nil }

    public init(
        call: PromptMCPResponseCall,
        mode: OffsendMCPResponseMode,
        secretTypes: [String],
        sealedOutput: String? = nil,
        sealedCount: Int = 0,
        fieldsTransformed: Int = 0,
        sealFailed: Bool = false,
        reason: String
    ) {
        self.call = call
        self.mode = mode
        self.secretTypes = secretTypes
        self.sealedOutput = sealedOutput
        self.sealedCount = sealedCount
        self.fieldsTransformed = fieldsTransformed
        self.sealFailed = sealFailed
        self.reason = reason
    }
}

/// Post-execution gate for MCP tool responses (`context.mcp.responses`).
///
/// Claude Code and current Cursor builds can replace MCP tool output before the
/// model sees it. Legacy Cursor `afterMCPExecution` inputs remain observe-only.
public enum PromptMCPResponseGate {
    /// Secondary direct-call guard (UTF-8 bytes). Installed hooks enforce the
    /// same limit on raw stdin before parsing.
    public static let maxResponseBytes = CheckHookLimits.maxStdinBytes

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
        sealedCount: Int = 0,
        fieldsTransformed: Int = 0,
        sealFailed: Bool = false
    ) -> PromptMCPResponseDecision {
        let mode = OffsendMCPRuleResolver.effectiveResponseMode(
            mcpConfig: mcpConfig,
            server: call.server,
            tool: call.tool
        )
        let hasSecrets = !secretTypes.isEmpty
        let hasFields = fieldsTransformed > 0
        guard hasSecrets || hasFields || (mode == .seal && (call.truncated || sealFailed)) else {
            return PromptMCPResponseDecision(
                call: call,
                mode: mode,
                secretTypes: [],
                reason: ""
            )
        }

        if !hasSecrets, !hasFields, mode == .seal, call.truncated {
            let handling = call.canReplaceOutput
                ? "and was withheld."
                : "— it could not be scanned or sealed safely."
            return PromptMCPResponseDecision(
                call: call,
                mode: mode,
                secretTypes: [],
                reason: "Offsend: MCP response from '\(call.server)/\(call.tool)' exceeded "
                    + "the safe sealing limit \(handling)"
            )
        }

        var reason = "Offsend: MCP response from '\(call.server)/\(call.tool)'"
        if hasSecrets {
            reason += " contains secrets (\(secretTypes.joined(separator: ", ")))"
        }
        if hasFields {
            reason += hasSecrets
                ? "; field policy transformed \(fieldsTransformed) value(s)"
                : " matched field policy (\(fieldsTransformed) value(s))"
        }
        reason += "."

        if sealedOutput != nil {
            reason += " Sensitive values were sealed as {{…}} tokens before reaching the agent."
        } else if mode == .seal, call.truncated {
            reason += call.canReplaceOutput
                ? " Response too large to seal safely — it was withheld."
                : " Response too large to seal safely — treat it as compromised context."
        } else if mode == .seal, sealFailed {
            reason += " Sealing failed — the response was withheld."
        } else if mode == .seal {
            reason += call.canReplaceOutput
                ? " Sealing unavailable (no seal key) — the response was withheld."
                : " Sealing unavailable (no seal key) — treat the values as exposed to the agent."
        } else {
            reason += " The values are now in agent context — rotate them if they are live."
        }
        return PromptMCPResponseDecision(
            call: call,
            mode: mode,
            secretTypes: secretTypes,
            sealedOutput: sealedOutput,
            sealedCount: sealedCount,
            fieldsTransformed: fieldsTransformed,
            sealFailed: sealFailed,
            reason: reason
        )
    }

    // MARK: - Extraction

    private static func extractCursorCall(from root: [String: Any]) -> PromptMCPResponseCall? {
        if root["tool_output"] != nil || root["toolOutput"] != nil {
            let rawTool = nonEmptyString(root["tool_name"])
                ?? nonEmptyString(root["toolName"])
                ?? "unknown"
            let parsedTool = PromptMCPGate.parseCursorMCPToolName(rawTool)
            let serialized = serializeJSONAware(root["tool_output"] ?? root["toolOutput"])
            let bounded = bounded(serialized.text)
            return PromptMCPResponseCall(
                server: parsedTool?.server ?? "unknown",
                tool: parsedTool?.tool ?? rawTool,
                responseText: bounded.text,
                truncated: bounded.truncated,
                canReplaceOutput: true,
                responseShape: serialized.shape
            )
        }

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
        let serialized = serializeJSONAware(root["result_json"] ?? root["resultJson"])
        let bounded = bounded(serialized.text)
        return PromptMCPResponseCall(
            server: server,
            tool: tool.isEmpty ? "unknown" : tool,
            responseText: bounded.text,
            truncated: bounded.truncated,
            responseShape: serialized.shape
        )
    }

    private static func extractClaudeCall(from root: [String: Any]) -> PromptMCPResponseCall? {
        let toolName = nonEmptyString(root["tool_name"])
            ?? nonEmptyString(root["toolName"])
            ?? ""
        guard let parsed = PromptMCPGate.parseClaudeMCPToolName(toolName) else { return nil }
        // Same as Cursor: stringified JSON objects/arrays get object/array shape
        // so `context.mcp.rules[].fields` can run.
        let serialized = serializeJSONAware(root["tool_response"] ?? root["toolResponse"])
        let bounded = bounded(serialized.text)
        return PromptMCPResponseCall(
            server: parsed.server,
            tool: parsed.tool,
            responseText: bounded.text,
            truncated: bounded.truncated,
            // Claude PostToolUse replaces output via `updatedToolOutput`.
            canReplaceOutput: true,
            responseShape: serialized.shape
        )
    }

    private static func bounded(_ text: String) -> (text: String, truncated: Bool) {
        guard text.utf8.count > maxResponseBytes else { return (text, false) }
        var end = text.startIndex
        var bytes = 0
        while end < text.endIndex {
            let next = text.index(after: end)
            let characterBytes = text[end..<next].utf8.count
            if bytes + characterBytes > maxResponseBytes { break }
            bytes += characterBytes
            end = next
        }
        return (String(text[..<end]), true)
    }

    private static func serialize(_ value: Any?) -> (text: String, shape: PromptMCPResponseShape) {
        guard let value else { return ("", .string) }
        if let string = value as? String { return (string, .string) }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return (string, shape(of: value))
        }
        return (String(describing: value), .scalar)
    }

    /// Serializes tool output and, when the payload is a JSON object/array encoded
    /// as a string, reports `.object` / `.array` so field rules can apply.
    private static func serializeJSONAware(
        _ value: Any?
    ) -> (text: String, shape: PromptMCPResponseShape) {
        let serialized = serialize(value)
        guard serialized.shape == .string,
              let data = serialized.text.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
              ) else {
            return serialized
        }
        return (serialized.text, shape(of: decoded))
    }

    private static func shape(of value: Any) -> PromptMCPResponseShape {
        if value is [String: Any] { return .object }
        if value is [Any] { return .array }
        if value is String { return .string }
        return .scalar
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

public enum PromptMCPResponseGateRenderer {
    public static func renderLimitExceeded(adapter: CheckHookAdapter) -> CheckHookAdapterOutput {
        let reason = "Offsend withheld this MCP response because it exceeded the safe input limit."
        switch adapter {
        case .cursor:
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "updated_mcp_tool_output": safeLimitReplacement(),
                    "additional_context": reason,
                ]),
                stderr: reason + "\n",
                exitCode: 0
            )
        case .claude:
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "hookSpecificOutput": [
                        "hookEventName": "PostToolUse",
                        "updatedToolOutput": reason,
                        "updatedMCPToolOutput": reason,
                        "additionalContext": reason,
                    ],
                ]),
                stderr: reason + "\n",
                exitCode: 0
            )
        case .windsurf, .codex:
            return CheckHookAdapterOutput(stdout: "", stderr: reason + "\n", exitCode: 0)
        }
    }

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
        guard decision.hasFindings else {
            return CheckHookAdapterOutput(stdout: "{}", stderr: "", exitCode: 0)
        }
        guard decision.call.canReplaceOutput else {
            return CheckHookAdapterOutput(
                stdout: "{}",
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        }

        switch decision.mode {
        case .observe:
            return CheckHookAdapterOutput(stdout: "{}", stderr: decision.reason + "\n", exitCode: 0)
        case .warn:
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "additional_context": decision.reason + " Do not echo, store, or reuse these values.",
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        case .seal:
            if decision.call.truncated {
                return CheckHookAdapterOutput(
                    stdout: jsonObject([
                        "updated_mcp_tool_output": safeLimitReplacement(),
                        "additional_context": decision.reason,
                    ]),
                    stderr: decision.reason + "\n",
                    exitCode: 0
                )
            }
            if decision.sealFailed {
                return CheckHookAdapterOutput(
                    stdout: jsonObject([
                        "updated_mcp_tool_output": sealFailureReplacement(),
                        "additional_context": decision.reason,
                    ]),
                    stderr: decision.reason + "\n",
                    exitCode: 0
                )
            }
            guard let sealedOutput = decision.sealedOutput else {
                return CheckHookAdapterOutput(
                    stdout: jsonObject([
                        "updated_mcp_tool_output": sealUnavailableReplacement(),
                        "additional_context": decision.reason,
                    ]),
                    stderr: decision.reason + "\n",
                    exitCode: 0
                )
            }
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "updated_mcp_tool_output": cursorReplacementObject(
                        from: sealedOutput,
                        shape: decision.call.responseShape
                    ),
                    "additional_context": "Offsend sealed \(decision.sealedCount) secret value(s) "
                        + "in this MCP response as {{TYPE:v1.…}} tokens.",
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        }
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
            if decision.call.truncated {
                let replacement = "Offsend withheld this MCP response because it exceeded the safe sealing limit."
                return CheckHookAdapterOutput(
                    stdout: jsonObject([
                        "hookSpecificOutput": [
                            "hookEventName": "PostToolUse",
                            "updatedToolOutput": replacement,
                            "updatedMCPToolOutput": replacement,
                            "additionalContext": decision.reason,
                        ],
                    ]),
                    stderr: decision.reason + "\n",
                    exitCode: 0
                )
            }
            if decision.sealFailed {
                let replacement = "Offsend withheld this MCP response because sealing its secrets failed."
                return CheckHookAdapterOutput(
                    stdout: jsonObject([
                        "hookSpecificOutput": [
                            "hookEventName": "PostToolUse",
                            "updatedToolOutput": replacement,
                            "updatedMCPToolOutput": replacement,
                            "additionalContext": decision.reason,
                        ],
                    ]),
                    stderr: decision.reason + "\n",
                    exitCode: 0
                )
            }
            guard let sealedOutput = decision.sealedOutput else {
                let replacement = "Offsend withheld this MCP response because no seal key is available."
                return CheckHookAdapterOutput(
                    stdout: jsonObject([
                        "hookSpecificOutput": [
                            "hookEventName": "PostToolUse",
                            "updatedToolOutput": replacement,
                            "updatedMCPToolOutput": replacement,
                            "additionalContext": decision.reason,
                        ],
                    ]),
                    stderr: decision.reason + "\n",
                    exitCode: 0
                )
            }
            // Claude `updatedToolOutput` is documented as a string; passing a
            // structured value risks a silently ignored replacement (secrets
            // would then reach the model), so the sealed text is sent verbatim.
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

    private static func cursorReplacementObject(
        from sealedOutput: String,
        shape: PromptMCPResponseShape
    ) -> [String: Any] {
        if shape == .object,
           let object = replacementValue(from: sealedOutput, shape: shape) as? [String: Any] {
            return object
        }
        return ["content": replacementValue(from: sealedOutput, shape: shape)]
    }

    private static func replacementValue(
        from sealedOutput: String,
        shape: PromptMCPResponseShape
    ) -> Any {
        guard shape != .string,
              let data = sealedOutput.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
              ) else {
            return sealedOutput
        }
        return value
    }

    private static func safeLimitReplacement() -> [String: Any] {
        [
            "error": "Offsend withheld this MCP response because it exceeded the safe sealing limit.",
        ]
    }

    private static func sealFailureReplacement() -> [String: Any] {
        [
            "error": "Offsend withheld this MCP response because sealing its secrets failed.",
        ]
    }

    private static func sealUnavailableReplacement() -> [String: Any] {
        [
            "error": "Offsend withheld this MCP response because no seal key is available.",
        ]
    }
}
