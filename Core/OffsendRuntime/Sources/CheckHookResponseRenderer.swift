import Foundation

/// Shared JSON encoding and fail-open shapes for AI-editor hook responses.
public enum CheckHookResponseRenderer {
    public enum Kind: Sendable {
        /// Cursor `beforeSubmitPrompt` / Claude `UserPromptSubmit` / etc.
        case promptSubmit
        /// Cursor `beforeReadFile` / Claude `PreToolUse` (Read).
        case readGate
        /// Cursor `preToolUse` (`Grep`) — content seal cannot rewrite search hits.
        case grepGate
        /// Cursor/Claude generic pre-tool hooks for Edit/Write.
        case writeGate
        /// Cursor `beforeShellExecution` / Claude `PreToolUse` (Bash).
        /// Same permission-shaped fail-open as the read gate.
        case shellGate
        /// Cursor `beforeMCPExecution` / Claude `PreToolUse` (MCP tools).
        case mcpGate
        /// Cursor `subagentStart` / `preToolUse` (`Task`).
        case subagentGate
        /// Cursor `postToolUse` / Claude `PostToolUse` (MCP tools).
        /// Post-execution transformation; never returns a permission shape.
        case mcpResponseGate
        /// Cursor `afterShellExecution` / Claude `PostToolUse` (Bash).
        /// Observational: the response can carry nothing the editor will act on.
        case shellAudit
    }

    /// Allow through after an infrastructure error. `reason` is a short public code.
    public static func failOpen(
        adapter: CheckHookAdapter,
        reason: String,
        kind: Kind
    ) -> CheckHookAdapterOutput {
        let stderr = "offsend: fail-open (\(adapter.rawValue)): \(reason)\n"
        switch kind {
        case .promptSubmit:
            switch adapter {
            case .cursor:
                return CheckHookAdapterOutput(
                    stdout: encodeJSONObject(["continue": true]),
                    stderr: stderr,
                    exitCode: 0
                )
            case .claude, .codex:
                return CheckHookAdapterOutput(stdout: "{}", stderr: stderr, exitCode: 0)
            case .windsurf:
                return CheckHookAdapterOutput(stdout: "", stderr: stderr, exitCode: 0)
            }
        case .readGate, .grepGate, .writeGate, .shellGate, .mcpGate, .subagentGate:
            switch adapter {
            case .cursor:
                return CheckHookAdapterOutput(
                    stdout: encodeJSONObject(["permission": "allow"]),
                    stderr: stderr,
                    exitCode: 0
                )
            case .claude:
                return CheckHookAdapterOutput(stdout: "{}", stderr: stderr, exitCode: 0)
            case .windsurf, .codex:
                return CheckHookAdapterOutput(stdout: "", stderr: stderr, exitCode: 0)
            }
        case .mcpResponseGate, .shellAudit:
            switch adapter {
            case .cursor, .claude:
                return CheckHookAdapterOutput(stdout: "{}", stderr: stderr, exitCode: 0)
            case .windsurf, .codex:
                return CheckHookAdapterOutput(stdout: "", stderr: stderr, exitCode: 0)
            }
        }
    }

    /// Stop an editor operation when a trusted policy exists but the live
    /// workspace policy no longer matches it.
    public static func failClosed(
        adapter: CheckHookAdapter,
        reason: String,
        kind: Kind
    ) -> CheckHookAdapterOutput {
        let message = "Offsend blocked this operation: \(reason). "
            + "Review .offsend.yml, then run `offsend policy trust` yourself in a terminal."
        let stderr = "offsend: fail-closed (\(adapter.rawValue)): policy_drift\n"
        switch kind {
        case .promptSubmit:
            switch adapter {
            case .cursor:
                return CheckHookAdapterOutput(
                    stdout: encodeJSONObject([
                        "continue": false,
                        "user_message": message,
                    ]),
                    stderr: stderr,
                    exitCode: 0
                )
            case .claude, .codex:
                return CheckHookAdapterOutput(
                    stdout: encodeJSONObject([
                        "decision": "block",
                        "reason": message,
                        "systemMessage": message,
                    ]),
                    stderr: stderr,
                    exitCode: 0
                )
            case .windsurf:
                return CheckHookAdapterOutput(
                    stdout: "",
                    stderr: message + "\n",
                    exitCode: OffsendExitCode.error.rawValue
                )
            }
        case .readGate, .grepGate, .writeGate, .shellGate, .mcpGate, .subagentGate:
            switch adapter {
            case .cursor:
                return CheckHookAdapterOutput(
                    stdout: encodeJSONObject([
                        "permission": "deny",
                        "user_message": message,
                        "agent_message": message,
                    ]),
                    stderr: stderr,
                    exitCode: 0
                )
            case .claude:
                return CheckHookAdapterOutput(
                    stdout: encodeJSONObject([
                        "hookSpecificOutput": [
                            "hookEventName": "PreToolUse",
                            "permissionDecision": "deny",
                            "permissionDecisionReason": message,
                        ],
                    ]),
                    stderr: stderr,
                    exitCode: 0
                )
            case .windsurf, .codex:
                return CheckHookAdapterOutput(stdout: "", stderr: message + "\n", exitCode: 2)
            }
        case .shellAudit:
            // Post-hoc and unable to change anything: there is nothing to fail
            // closed onto, so drift is reported on stderr only.
            return CheckHookAdapterOutput(stdout: "{}", stderr: stderr, exitCode: 0)
        case .mcpResponseGate:
            switch adapter {
            case .cursor:
                return CheckHookAdapterOutput(
                    stdout: encodeJSONObject([
                        "updated_mcp_tool_output": ["error": message],
                        "additional_context": message,
                    ]),
                    stderr: stderr,
                    exitCode: 0
                )
            case .claude:
                return CheckHookAdapterOutput(
                    stdout: encodeJSONObject([
                        "hookSpecificOutput": [
                            "hookEventName": "PostToolUse",
                            "updatedToolOutput": message,
                            "updatedMCPToolOutput": message,
                            "additionalContext": message,
                        ],
                    ]),
                    stderr: stderr,
                    exitCode: 0
                )
            case .windsurf, .codex:
                return CheckHookAdapterOutput(stdout: "", stderr: message + "\n", exitCode: 2)
            }
        }
    }

    public static func encodeJSONObject(_ object: [String: Any]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}
