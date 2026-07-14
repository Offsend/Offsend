import Foundation

/// Shared JSON encoding and fail-open shapes for AI-editor hook responses.
public enum CheckHookResponseRenderer {
    public enum Kind: Sendable {
        /// Cursor `beforeSubmitPrompt` / Claude `UserPromptSubmit` / etc.
        case promptSubmit
        /// Cursor `beforeReadFile` / Claude `PreToolUse` (Read).
        case readGate
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
        case .readGate:
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
