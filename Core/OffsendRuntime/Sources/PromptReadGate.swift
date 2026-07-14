import Foundation

public struct PromptReadGateDecision: Equatable, Sendable {
    public let path: String
    public let allowed: Bool
    public let reason: String

    public init(path: String, allowed: Bool, reason: String) {
        self.path = path
        self.allowed = allowed
        self.reason = reason
    }
}

/// Path denylist for Cursor `beforeReadFile` / Claude `PreToolUse` (Read) — no file content read.
public enum PromptReadGate {
    public static func evaluate(json: String, adapter: CheckHookAdapter) throws -> PromptReadGateDecision {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        guard let path = extractPath(from: object, adapter: adapter) else {
            // Missing path → fail-open at call site; treat as allow here only if we got a path.
            throw PromptHookInputError.invalidJSON
        }
        if PromptAttachmentAdvisor.isSuspicious(path: path) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return PromptReadGateDecision(
                path: path,
                allowed: false,
                reason: "Offsend: blocked reading sensitive path (\(name)). Run `offsend ignore '\(name)'` or use env secrets."
            )
        }
        return PromptReadGateDecision(path: path, allowed: true, reason: "")
    }

    public static func extractPath(from root: [String: Any], adapter: CheckHookAdapter) -> String? {
        switch adapter {
        case .cursor:
            if let path = root["file_path"] as? String, !path.isEmpty { return path }
            if let path = root["filePath"] as? String, !path.isEmpty { return path }
            if let path = root["path"] as? String, !path.isEmpty { return path }
            return nil
        case .claude:
            if let toolInput = root["tool_input"] as? [String: Any] {
                if let path = toolInput["file_path"] as? String, !path.isEmpty { return path }
                if let path = toolInput["path"] as? String, !path.isEmpty { return path }
            }
            if let path = root["file_path"] as? String, !path.isEmpty { return path }
            return nil
        case .windsurf, .codex:
            return nil
        }
    }
}

public enum PromptReadGateRenderer {
    /// Fail-open for file-read hooks (must use read-gate JSON, not prompt-submit shape).
    public static func failOpen(
        adapter: CheckHookAdapter,
        reason: String
    ) -> CheckHookAdapterOutput {
        CheckHookResponseRenderer.failOpen(
            adapter: adapter,
            reason: reason,
            kind: .readGate
        )
    }

    public static func render(
        decision: PromptReadGateDecision,
        adapter: CheckHookAdapter
    ) -> CheckHookAdapterOutput {
        switch adapter {
        case .cursor:
            if decision.allowed {
                return CheckHookAdapterOutput(
                    stdout: jsonObject(["permission": "allow"]),
                    stderr: "",
                    exitCode: 0
                )
            }
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "permission": "deny",
                    "user_message": decision.reason,
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        case .claude:
            if decision.allowed {
                return CheckHookAdapterOutput(stdout: "{}", stderr: "", exitCode: 0)
            }
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "decision": "block",
                    "reason": decision.reason,
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        case .windsurf, .codex:
            return CheckHookAdapterOutput(stdout: "", stderr: "", exitCode: 0)
        }
    }

    private static func jsonObject(_ object: [String: Any]) -> String {
        CheckHookResponseRenderer.encodeJSONObject(object)
    }
}
