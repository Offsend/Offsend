import Foundation

public struct PromptShellGateDecision: Equatable, Sendable {
    public let command: String
    /// Sensitive-looking path tokens found in the command.
    public let suspiciousPaths: [String]
    public let reason: String

    public var allowed: Bool { suspiciousPaths.isEmpty }

    public init(command: String, suspiciousPaths: [String], reason: String) {
        self.command = command
        self.suspiciousPaths = suspiciousPaths
        self.reason = reason
    }
}

/// Best-effort gate for Cursor `beforeShellExecution` / Claude `PreToolUse` (Bash).
/// Tokenizes the command and flags sensitive path tokens (same heuristics as the
/// read-gate path heuristics, including symlink targets when the path exists).
/// Does not parse shell grammar and never reads file contents; findings ask for
/// user confirmation instead of blocking.
public enum PromptShellGate {
    public static func evaluate(json: String, adapter: CheckHookAdapter) throws -> PromptShellGateDecision {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        guard let command = extractCommand(from: root, adapter: adapter) else {
            throw PromptHookInputError.invalidJSON
        }
        let cwd = (root["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return evaluate(command: command, cwd: cwd)
    }

    public static func evaluate(command: String, cwd: String? = nil) -> PromptShellGateDecision {
        // `offsend unseal` restores sealed plaintext; the agent must not quietly
        // unseal what the read/MCP gates just sealed. Ask the user first.
        if referencesUnseal(command) {
            return PromptShellGateDecision(
                command: command,
                suspiciousPaths: ["offsend unseal"],
                reason: "Offsend: command runs `offsend unseal` — it restores sealed secrets to plaintext. "
                    + "Confirm before running; unseal output belongs to the user, not the agent context."
            )
        }
        var seen = Set<String>()
        var suspicious: [String] = []
        for candidate in pathCandidates(in: command) {
            guard let name = firstSuspiciousBasename(in: candidate, cwd: cwd) else { continue }
            if seen.insert(name.lowercased()).inserted {
                suspicious.append(name)
            }
        }
        guard !suspicious.isEmpty else {
            return PromptShellGateDecision(command: command, suspiciousPaths: [], reason: "")
        }
        let names = suspicious.joined(separator: ", ")
        return PromptShellGateDecision(
            command: command,
            suspiciousPaths: suspicious,
            reason: "Offsend: command touches sensitive path (\(names)). "
                + "Confirm before running — secrets can fuel further tool use."
        )
    }

    /// True when the command invokes `offsend … unseal` (any path to the binary).
    static func referencesUnseal(_ command: String) -> Bool {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.contains("unseal") else { return false }
        return tokens.contains { token in
            let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            return trimmed == "offsend" || trimmed.hasSuffix("/offsend")
        }
    }

    /// Raw token first (covers `~/.ssh/…` without expanding), then absolute + symlink target.
    private static func firstSuspiciousBasename(in candidate: String, cwd: String?) -> String? {
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

    public static func extractCommand(from root: [String: Any], adapter: CheckHookAdapter) -> String? {
        switch adapter {
        case .cursor:
            if let command = root["command"] as? String, !command.isEmpty { return command }
            return nil
        case .claude:
            if let toolInput = root["tool_input"] as? [String: Any],
               let command = toolInput["command"] as? String, !command.isEmpty {
                return command
            }
            if let command = root["command"] as? String, !command.isEmpty { return command }
            return nil
        case .windsurf, .codex:
            return nil
        }
    }

    /// Whitespace tokens with shell punctuation stripped; `VAR=value` and
    /// `--flag=value` contribute the value part.
    static func pathCandidates(in command: String) -> [String] {
        let strippable = CharacterSet(charactersIn: "\"'`()<>;|&,")
        var candidates: [String] = []
        for rawToken in command.split(whereSeparator: \.isWhitespace) {
            var token = String(rawToken).trimmingCharacters(in: strippable)
            if let equals = token.firstIndex(of: "=") {
                token = String(token[token.index(after: equals)...])
                    .trimmingCharacters(in: strippable)
            }
            guard !token.isEmpty, !token.hasPrefix("-") else { continue }
            candidates.append(token)
        }
        return candidates
    }
}

public enum PromptShellGateRenderer {
    /// Findings produce `ask` (user confirmation), never a hard deny.
    public static func render(
        decision: PromptShellGateDecision,
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
                    "permission": "ask",
                    "user_message": decision.reason,
                    "agent_message": "The command references sensitive files (\(decision.suspiciousPaths.joined(separator: ", "))). Ask the user before reading secret material — credentials can fuel further tool use. Prefer env vars / AI ignore files.",
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
                    "hookSpecificOutput": [
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "ask",
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
