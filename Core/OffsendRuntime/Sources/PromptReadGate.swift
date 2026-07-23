import DetectionCore
import Foundation

public struct PromptReadGateDecision: Equatable, Sendable {
    public let path: String
    public let allowed: Bool
    public let reason: String
    /// Extra guidance for the agent (Cursor `agent_message`; appended to the
    /// Claude `permissionDecisionReason`). Used by seal-mode denies to hand the
    /// agent the sealed-copy path.
    public let agentMessage: String?

    public init(path: String, allowed: Bool, reason: String, agentMessage: String? = nil) {
        self.path = path
        self.allowed = allowed
        self.reason = reason
        self.agentMessage = agentMessage
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

public enum PromptReadGateContentResolution: Equatable, Sendable {
    case content(String)
    case oversized
    case unavailable
}

/// Path denylist + optional secrets scan for Cursor `beforeReadFile` / Claude `PreToolUse` (Read).
public enum PromptReadGate {
    /// Full-content budget for hook payloads and disk fallback.
    public static let maxContentBytes = CheckHookLimits.maxStdinBytes

    public static func parse(json: String, adapter: CheckHookAdapter) throws -> PromptReadGateInput {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        guard let path = extractPath(from: object, adapter: adapter) else {
            throw PromptHookInputError.invalidJSON
        }
        let cwd = (object["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let content = extractContent(from: object, adapter: adapter)
        return PromptReadGateInput(path: resolveFilesystemPath(path, cwd: cwd), content: content)
    }

    /// Absolute paths pass through; relative paths resolve against `cwd` or the process cwd.
    public static func resolveFilesystemPath(_ path: String, cwd: String?) -> String {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        let base = cwd.flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.currentDirectoryPath
        // `isDirectory: true` keeps the last cwd segment (Foundation otherwise treats it as a file).
        let baseURL = URL(fileURLWithPath: base, isDirectory: true)
        return URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL.path
    }

    /// Presented path plus symlink-resolved target when it differs (benign link name → `.env`).
    public static func sensitivityCheckPaths(for path: String, cwd: String? = nil) -> [String] {
        let absolute = resolveFilesystemPath(path, cwd: cwd)
        var paths = [absolute]
        let resolved = URL(fileURLWithPath: absolute).resolvingSymlinksInPath().path
        if resolved != absolute {
            paths.append(resolved)
        }
        return paths
    }

    /// True when the read target falls under `check.exclude` (unless
    /// `hooks.ignore_exclude` disabled this, which callers handle by passing
    /// empty patterns). Both the presented path and its symlink-resolved target
    /// must be inside the project root and excluded, so a benign excluded link
    /// name cannot smuggle a sensitive target past the gate.
    public static func isExcluded(
        path: String,
        excludePatterns: [String],
        projectRoot: URL
    ) -> Bool {
        guard !excludePatterns.isEmpty else { return false }
        let rootPath = projectRoot.standardizedFileURL.path
        return sensitivityCheckPaths(for: path).allSatisfy { candidate in
            guard candidate.hasPrefix(rootPath + "/") else { return false }
            let relative = String(candidate.dropFirst(rootPath.count + 1))
            return PathExcludeMatcher.isExcluded(relativePath: relative, patterns: excludePatterns)
        }
    }

    /// Path denylist only (no content scan). Prefer `evaluate` with entities for full gate behavior.
    public static func evaluate(json: String, adapter: CheckHookAdapter) throws -> PromptReadGateDecision {
        let input = try parse(json: json, adapter: adapter)
        return evaluatePath(input.path)
    }

    public static func evaluatePath(_ path: String) -> PromptReadGateDecision {
        for candidate in sensitivityCheckPaths(for: path) {
            guard PromptAttachmentAdvisor.isSuspicious(path: candidate) else { continue }
            let name = URL(fileURLWithPath: candidate).lastPathComponent
            return PromptReadGateDecision(
                path: path,
                allowed: false,
                reason: "Offsend: blocked reading sensitive path (\(name)) — keep credentials out of agent context. "
                    + "Use env secrets or `offsend ignore '\(name)'`."
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
                + "Keep them out of agent context (env / secret manager), or `offsend ignore` the path."
        )
    }

    /// Deny that points the agent at a sealed copy instead of a dead end
    /// (`context.read.on_secret: seal`). Plaintext stays out of the transcript;
    /// secret values in the copy are `{{TYPE:v1.…}}` tokens.
    public static func sealedDecision(
        path: String,
        sealedCopyPath: String,
        secretTypes: [String]
    ) -> PromptReadGateDecision {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let typeList = secretTypes.joined(separator: ", ")
        return PromptReadGateDecision(
            path: path,
            allowed: false,
            reason: "Offsend: blocked reading \(name) — contains secrets (\(typeList)). "
                + "Sealed copy (secrets → {{…}} tokens): \(sealedCopyPath)",
            agentMessage: "Read the sealed copy instead: \(sealedCopyPath). "
                + "Secret values are sealed as {{TYPE:v1.…}} tokens — keep them verbatim; "
                + "the user can restore outputs with `offsend unseal`."
        )
    }

    public static func oversizedDecision(path: String) -> PromptReadGateDecision {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return PromptReadGateDecision(
            path: path,
            allowed: false,
            reason: "Offsend: blocked reading \(name) — content exceeds the "
                + "\(maxContentBytes)-byte safety limit and cannot be fully scanned."
        )
    }

    /// Deny for hook input over the stdin byte limit: the payload was never
    /// parsed, so the path is unknown. Same fail-closed policy as
    /// `oversizedDecision` — an unscannable read must not pass.
    public static func oversizedStdinDecision() -> PromptReadGateDecision {
        PromptReadGateDecision(
            path: "",
            allowed: false,
            reason: "Offsend: blocked this file read — hook input exceeds the "
                + "\(maxContentBytes)-byte safety limit and cannot be scanned."
        )
    }

    public static func contentExceedsLimit(for input: PromptReadGateInput) -> Bool {
        resolveContentResult(for: input) == .oversized
    }

    /// Full content from hook JSON, else a bounded complete UTF-8 file from disk.
    public static func resolveContent(for input: PromptReadGateInput) -> String? {
        guard case let .content(content) = resolveContentResult(for: input) else {
            return nil
        }
        return content
    }

    /// Resolves content and distinguishes an oversized input from other
    /// unscannable files using the bytes actually read, not path metadata.
    public static func resolveContentResult(
        for input: PromptReadGateInput
    ) -> PromptReadGateContentResolution {
        if let content = input.content, !content.isEmpty {
            guard content.utf8.count <= maxContentBytes else { return .oversized }
            return .content(content)
        }
        return loadContentResult(fromPath: input.path)
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
        guard case let .content(content) = loadContentResult(fromPath: path) else {
            return nil
        }
        return content
    }

    private static func loadContentResult(
        fromPath path: String
    ) -> PromptReadGateContentResolution {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return .unavailable
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unavailable }
        defer { try? handle.close() }

        // Read one extra byte so an oversized file cannot be mistaken for a
        // complete safe prefix.
        let byteBudget = maxContentBytes + 1
        let data: Data
        if #available(macOS 10.15.4, iOS 13.4, *) {
            guard let chunk = try? handle.read(upToCount: byteBudget) else { return .unavailable }
            data = chunk
        } else {
            data = handle.readData(ofLength: byteBudget)
        }
        guard data.count <= maxContentBytes else { return .oversized }
        guard !data.isEmpty, !data.contains(0) else { return .unavailable }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return .unavailable
        }
        return .content(text)
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
            var payload: [String: Any] = [
                "permission": "deny",
                "user_message": decision.reason,
            ]
            if let agentMessage = decision.agentMessage {
                payload["agent_message"] = agentMessage
            }
            return CheckHookAdapterOutput(
                stdout: jsonObject(payload),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        case .claude:
            if decision.allowed {
                return CheckHookAdapterOutput(stdout: "{}", stderr: "", exitCode: 0)
            }
            // PreToolUse requires hookSpecificOutput.permissionDecision (top-level
            // decision/reason is deprecated and ignored by current Claude Code).
            // The reason reaches the model, so the agent message is appended there.
            let reason = [decision.reason, decision.agentMessage]
                .compactMap { $0 }
                .joined(separator: " ")
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "hookSpecificOutput": [
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": reason,
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
