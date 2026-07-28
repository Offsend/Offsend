import Foundation

public enum PromptGrepGatePermission: String, Equatable, Sendable {
    case allow
    case deny
}

public struct PromptGrepGateCall: Equatable, Sendable {
    /// Absolute path when Grep targets a single file; nil for workspace / directory search.
    public let path: String?
    public let pattern: String?

    public init(path: String? = nil, pattern: String? = nil) {
        self.path = path
        self.pattern = pattern
    }
}

public struct PromptGrepGateDecision: Equatable, Sendable {
    public let call: PromptGrepGateCall
    public let permission: PromptGrepGatePermission
    public let reason: String
    public let agentMessage: String?
    public let code: String
    public let secretTypes: [String]

    public var allowed: Bool { permission == .allow }

    public init(
        call: PromptGrepGateCall,
        permission: PromptGrepGatePermission,
        reason: String,
        agentMessage: String? = nil,
        code: String,
        secretTypes: [String] = []
    ) {
        self.call = call
        self.permission = permission
        self.reason = reason
        self.agentMessage = agentMessage
        self.code = code
        self.secretTypes = secretTypes
    }
}

/// Cursor `preToolUse` (`Grep`) gate.
///
/// Cursor `postToolUse` can replace MCP output only (`updated_mcp_tool_output`),
/// so Grep match bodies cannot be sealed. Under `context.read.on_secret: seal`
/// this gate denies Grep and points the agent at Read (which seals). Otherwise
/// it content-scans a single-file target and denies on secret hits.
public enum PromptGrepGate {
    public static func parse(json: String, adapter: CheckHookAdapter) throws -> PromptGrepGateCall {
        guard adapter == .cursor else {
            throw PromptHookInputError.invalidJSON
        }
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        return extractCall(from: root)
    }

    public static func extractCall(from root: [String: Any]) -> PromptGrepGateCall {
        let toolInput = root["tool_input"] as? [String: Any] ?? [:]
        let cwd = (root["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let pattern = string(in: toolInput, keys: ["pattern", "query", "regex"])
            ?? string(in: root, keys: ["pattern", "query", "regex"])
        let rawPath = string(in: toolInput, keys: ["path", "file_path", "filePath", "file"])
            ?? string(in: root, keys: ["path", "file_path", "filePath", "file"])
        let path: String?
        if let rawPath, !rawPath.isEmpty {
            let resolved = PromptReadGate.resolveFilesystemPath(rawPath, cwd: cwd)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                path = resolved
            } else {
                path = nil
            }
        } else {
            path = nil
        }
        return PromptGrepGateCall(path: path, pattern: pattern)
    }

    public static func evaluate(
        call: PromptGrepGateCall,
        readConfig: OffsendProjectReadConfig? = nil,
        secretTypes: [String] = []
    ) -> PromptGrepGateDecision {
        let sealMode = OffsendReadGateSecretMode(rawValue: readConfig?.onSecret ?? "") == .seal

        // Cursor cannot rewrite Grep tool_output — seal mode would leave plaintext
        // in context, so deny the tool and send the agent to Read.
        if sealMode {
            let reason = "Offsend: Grep is denied when context.read.on_secret is seal "
                + "(Cursor cannot seal search results). Use the Read tool instead."
            return PromptGrepGateDecision(
                call: call,
                permission: .deny,
                reason: reason,
                agentMessage: reason,
                code: "seal_no_grep_rewrite",
                secretTypes: []
            )
        }

        guard !secretTypes.isEmpty else {
            return PromptGrepGateDecision(
                call: call,
                permission: .allow,
                reason: "",
                code: "allow"
            )
        }

        let typeList = secretTypes.joined(separator: ", ")
        let reason = "Offsend: Grep target contains secrets (\(typeList)). Use Read instead."
        return PromptGrepGateDecision(
            call: call,
            permission: .deny,
            reason: reason,
            agentMessage: reason,
            code: "secrets",
            secretTypes: secretTypes
        )
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

public enum PromptGrepGateRenderer {
    public static func render(
        decision: PromptGrepGateDecision,
        adapter: CheckHookAdapter
    ) -> CheckHookAdapterOutput {
        switch adapter {
        case .cursor:
            switch decision.permission {
            case .allow:
                return CheckHookAdapterOutput(
                    stdout: CheckHookResponseRenderer.encodeJSONObject(["permission": "allow"]),
                    stderr: "",
                    exitCode: 0
                )
            case .deny:
                var payload: [String: Any] = [
                    "permission": "deny",
                    "user_message": decision.reason,
                ]
                if let agentMessage = decision.agentMessage, !agentMessage.isEmpty {
                    payload["agent_message"] = agentMessage
                }
                return CheckHookAdapterOutput(
                    stdout: CheckHookResponseRenderer.encodeJSONObject(payload),
                    stderr: decision.reason + "\n",
                    exitCode: 0
                )
            }
        case .claude, .windsurf, .codex:
            return CheckHookAdapterOutput(stdout: "", stderr: "", exitCode: 0)
        }
    }
}
