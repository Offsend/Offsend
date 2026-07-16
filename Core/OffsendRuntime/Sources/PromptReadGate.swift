import DetectionCore
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

public struct PromptReadGateInput: Equatable, Sendable {
    public let path: String
    /// File body from the editor hook payload when present (Cursor `beforeReadFile`).
    public let content: String?

    public init(path: String, content: String?) {
        self.path = path
        self.content = content
    }
}

/// Path denylist + optional secrets scan for Cursor `beforeReadFile` / Claude `PreToolUse` (Read).
public enum PromptReadGate {
    /// Cap for disk fallback / scan window (matches default detection `maximumLength`).
    public static let maxContentCharacters = 50_000

    public static func parse(json: String, adapter: CheckHookAdapter) throws -> PromptReadGateInput {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        guard let path = extractPath(from: object, adapter: adapter) else {
            throw PromptHookInputError.invalidJSON
        }
        let content = extractContent(from: object, adapter: adapter)
        return PromptReadGateInput(path: path, content: content)
    }

    /// Path denylist only (no content scan). Prefer `evaluate` with entities for full gate behavior.
    public static func evaluate(json: String, adapter: CheckHookAdapter) throws -> PromptReadGateDecision {
        let input = try parse(json: json, adapter: adapter)
        return evaluatePath(input.path)
    }

    public static func evaluatePath(_ path: String) -> PromptReadGateDecision {
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

    /// Deny when secret-shaped entities are present; `nil` means allow (no secret findings).
    public static func decisionForSecretEntities(
        path: String,
        entities: [SensitiveEntity],
        secretsOnly: Bool = true
    ) -> PromptReadGateDecision? {
        let secrets = PromptCheckAdviceBuilder.filterEntities(entities, secretsOnly: secretsOnly)
        guard !secrets.isEmpty else { return nil }

        let name = URL(fileURLWithPath: path).lastPathComponent
        let types = Array(Set(secrets.map(\.type.rawValue))).sorted()
        let typeList = types.joined(separator: ", ")
        return PromptReadGateDecision(
            path: path,
            allowed: false,
            reason: "Offsend: blocked reading \(name) — contains secrets (\(typeList)). "
                + "Move secrets to env / secret manager, or add the path via `offsend ignore`."
        )
    }

    /// Content from the hook JSON, else a bounded UTF-8 prefix from disk (Claude has no body in PreToolUse).
    public static func resolveContent(for input: PromptReadGateInput) -> String? {
        if let content = input.content, !content.isEmpty {
            return String(content.prefix(maxContentCharacters))
        }
        return loadContentPrefix(fromPath: input.path)
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

    public static func extractContent(from root: [String: Any], adapter: CheckHookAdapter) -> String? {
        switch adapter {
        case .cursor:
            if let content = root["content"] as? String { return content }
            return nil
        case .claude:
            // PreToolUse normally has no body; accept `content` if an adapter ever forwards it.
            if let content = root["content"] as? String { return content }
            if let toolInput = root["tool_input"] as? [String: Any],
               let content = toolInput["content"] as? String {
                return content
            }
            return nil
        case .windsurf, .codex:
            return nil
        }
    }

    /// Best-effort disk read for Claude (and Cursor when content is omitted). Failures → nil (caller allows).
    public static func loadContentPrefix(fromPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // Read a byte budget large enough for typical UTF-8 of `maxContentCharacters`.
        let byteBudget = maxContentCharacters * 4
        let data: Data
        if #available(macOS 10.15.4, iOS 13.4, *) {
            guard let chunk = try? handle.read(upToCount: byteBudget) else { return nil }
            data = chunk
        } else {
            data = handle.readData(ofLength: byteBudget)
        }
        guard !data.isEmpty, !data.contains(0) else { return nil }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return String(text.prefix(maxContentCharacters))
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
            // PreToolUse requires hookSpecificOutput.permissionDecision (top-level
            // decision/reason is deprecated and ignored by current Claude Code).
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "hookSpecificOutput": [
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": decision.reason,
                    ],
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
