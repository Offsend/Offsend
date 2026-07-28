import Foundation

public struct PromptWriteGateInput: Equatable, Sendable {
    public let toolName: String
    /// Every filesystem path this tool call targets, in payload order.
    public let paths: [String]
    public let content: String?
    /// Text each edit replaces. Empty for a whole-file write, which carries its
    /// keys in `content`; an edit may carry only a bare value.
    public let replacedTexts: [String]

    /// Primary target; empty only for the synthetic decisions below.
    public var path: String { paths.first ?? "" }

    public init(
        toolName: String,
        paths: [String],
        content: String?,
        replacedTexts: [String] = []
    ) {
        self.toolName = toolName
        self.paths = paths
        self.content = content
        self.replacedTexts = replacedTexts
    }

    public init(
        toolName: String,
        path: String,
        content: String?,
        replacedTexts: [String] = []
    ) {
        self.init(
            toolName: toolName,
            paths: path.isEmpty ? [] : [path],
            content: content,
            replacedTexts: replacedTexts
        )
    }
}

public enum PromptWriteGatePermission: String, Equatable, Sendable {
    case allow
    case ask
    case deny
}

public struct PromptWriteGateDecision: Equatable, Sendable {
    public let input: PromptWriteGateInput
    public let permission: PromptWriteGatePermission
    public let reason: String
    public let artifact: ExecutableArtifactMatch?

    public var allowed: Bool { permission == .allow }

    public init(
        input: PromptWriteGateInput,
        permission: PromptWriteGatePermission,
        reason: String,
        artifact: ExecutableArtifactMatch?
    ) {
        self.input = input
        self.permission = permission
        self.reason = reason
        self.artifact = artifact
    }
}

/// Blocks agent file tools from mutating workspace configuration that a host
/// process may later execute outside the agent sandbox.
public enum PromptWriteGate {
    /// `adapter` completes the signature the other gates share, but this parser
    /// deliberately ignores it: reading both payload shapes for every editor is
    /// what keeps a renamed field or a schema change from turning the gate into
    /// a no-op for one of them.
    public static func parse(json: String, adapter: CheckHookAdapter) throws -> PromptWriteGateInput {
        guard let data = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }

        // Cursor `afterFileEdit` puts `file_path` at the root with no `tool_input`,
        // so both levels are searched.
        let toolInput = root["tool_input"] as? [String: Any] ?? [:]
        let scope = toolInput.isEmpty ? root : toolInput
        let toolName = (root["tool_name"] as? String)
            ?? (root["toolName"] as? String)
            ?? ""

        var paths = strings(in: toolInput, keys: pathKeys)
        if paths.isEmpty {
            paths = strings(in: root, keys: pathKeys)
        }
        if paths.isEmpty {
            // Cursor does not publish the `tool_input` schema for its file tools,
            // and tool sets change between releases. Rather than fail on an
            // unfamiliar key name, classify every path-shaped value in the payload.
            paths = pathLikeValues(in: scope)
        }
        guard !paths.isEmpty else {
            throw PromptHookInputError.invalidJSON
        }

        let cwd = (root["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return PromptWriteGateInput(
            toolName: toolName,
            paths: paths.map { PromptReadGate.resolveFilesystemPath($0, cwd: cwd) },
            content: content(in: scope),
            replacedTexts: replacedTexts(in: scope)
        )
    }

    /// A tool call is only as safe as its most dangerous target, so every path is
    /// classified and the strongest decision wins.
    public static func evaluate(
        input: PromptWriteGateInput,
        classifier: ExecutableArtifactClassifier
    ) -> PromptWriteGateDecision {
        var best: PromptWriteGateDecision?
        for path in input.paths {
            let decision = evaluate(path: path, input: input, classifier: classifier)
            if decision.permission == .deny {
                return decision
            }
            guard let current = best else {
                best = decision
                continue
            }
            if strictness(decision.permission) > strictness(current.permission) {
                best = decision
            } else if strictness(decision.permission) == strictness(current.permission),
                      current.artifact == nil {
                // Same outcome, but this target is a classified trust surface —
                // keep it so the provenance ledger and doctor can name it.
                best = decision
            }
        }
        return best ?? PromptWriteGateDecision(
            input: input,
            permission: .allow,
            reason: "",
            artifact: nil
        )
    }

    private static func strictness(_ permission: PromptWriteGatePermission) -> Int {
        switch permission {
        case .allow: return 0
        case .ask: return 1
        case .deny: return 2
        }
    }

    private static func evaluate(
        path: String,
        input: PromptWriteGateInput,
        classifier: ExecutableArtifactClassifier
    ) -> PromptWriteGateDecision {
        let artifact = classifier.classify(path: path)
        let name = URL(fileURLWithPath: path).lastPathComponent

        switch artifact?.enforcement {
        case nil, .observe:
            return PromptWriteGateDecision(
                input: input,
                permission: .allow,
                reason: "",
                artifact: artifact
            )
        case .deny:
            return PromptWriteGateDecision(
                input: input,
                permission: .deny,
                reason: "Offsend blocked the agent from modifying executable workspace configuration (\(name)). "
                    + "Review and edit this trust surface manually outside the agent session.",
                artifact: artifact
            )
        case .denyWhenContentExecutable:
            guard let content = input.content else {
                return PromptWriteGateDecision(
                    input: input,
                    permission: .ask,
                    reason: "Offsend could not inspect this change to \(name), which can carry "
                        + "execution-sensitive settings. Confirm the edit before allowing it.",
                    artifact: artifact
                )
            }
            guard touchesExecutableSetting(path: path, content: content, input: input) else {
                return PromptWriteGateDecision(
                    input: input,
                    permission: .allow,
                    reason: "",
                    artifact: artifact
                )
            }
            return PromptWriteGateDecision(
                input: input,
                permission: .deny,
                reason: "Offsend blocked the agent from adding or changing an execution-sensitive setting "
                    + "in \(name). Interpreter paths, terminal profiles, and task commands run outside the "
                    + "agent sandbox; edit them manually.",
                artifact: artifact
            )
        }
    }

    /// Settings files mix ordinary preferences with execution, so the decision
    /// turns on what the write does rather than on the file alone. A whole-file
    /// write carries its keys; an edit may carry only the replacement value, in
    /// which case the file on disk is what says whether that value belongs to an
    /// execution-sensitive key.
    private static func touchesExecutableSetting(
        path: String,
        content: String,
        input: PromptWriteGateInput
    ) -> Bool {
        if ExecutableConfigContentInspector.introducesExecutableSetting(content) {
            return true
        }
        guard !input.replacedTexts.isEmpty else { return false }
        if input.replacedTexts.contains(
            where: ExecutableConfigContentInspector.introducesExecutableSetting
        ) {
            return true
        }
        guard let existing = readForInspection(path: path) else { return false }
        return input.replacedTexts.contains {
            ExecutableConfigContentInspector.rewritesExecutableSetting(existing: existing, replaced: $0)
        }
    }

    static let maxInspectedFileBytes = 1024 * 1024

    private static func readForInspection(path: String) -> String? {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue <= maxInspectedFileBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// The editor delivered no payload at all. Cursor is known to do this for
    /// `preToolUse` in remote workspaces, which would otherwise look like an
    /// unparseable payload and block every write without explaining why.
    public static func emptyInputDecision() -> PromptWriteGateDecision {
        PromptWriteGateDecision(
            input: PromptWriteGateInput(toolName: "", path: "", content: nil),
            permission: .ask,
            reason: "Offsend received an empty pre-write hook payload, so it cannot see which file "
                + "is being written. Known to happen in Cursor remote workspaces; update the editor, "
                + "or re-run `offsend hook install --no-write-gate` to accept the risk.",
            artifact: nil
        )
    }

    /// Unrecognized hook payloads ask instead of denying: an editor schema
    /// change must not silently block every agent write.
    public static func invalidInputDecision() -> PromptWriteGateDecision {
        PromptWriteGateDecision(
            input: PromptWriteGateInput(toolName: "", path: "", content: nil),
            permission: .ask,
            reason: "Offsend could not read this file write (unrecognized pre-write hook input). "
                + "Confirm the change, and run `offsend doctor` if this repeats.",
            artifact: nil
        )
    }

    public static func oversizedInputDecision() -> PromptWriteGateDecision {
        PromptWriteGateDecision(
            input: PromptWriteGateInput(toolName: "", path: "", content: nil),
            permission: .ask,
            reason: "Offsend could not inspect this file write because the pre-write hook input "
                + "exceeded the safety limit. Confirm the change before allowing it.",
            artifact: nil
        )
    }

    private static let pathKeys = [
        "file_path", "filePath", "path", "paths",
        "target_file", "targetFile", "notebook_path", "notebookPath",
    ]
    private static let contentKeys = [
        "content", "contents", "new_string", "newString",
        "file_text", "fileText", "new_source", "newSource",
    ]
    /// Envelope fields that carry a path but are not the tool's target.
    private static let envelopeKeys: Set<String> = [
        "cwd", "transcript_path", "session_id", "tool_use_id",
        "hook_event_name", "tool_name", "workspace_roots", "permission_mode",
    ]

    /// String values for `keys`, accepting both a scalar and an array of paths.
    private static func strings(in object: [String: Any], keys: [String]) -> [String] {
        var found: [String] = []
        for key in keys {
            switch object[key] {
            case let value as String where !value.isEmpty:
                found.append(value)
            case let values as [Any]:
                found.append(contentsOf: values.compactMap { $0 as? String }.filter { !$0.isEmpty })
            default:
                continue
            }
        }
        return found
    }

    /// Text the tool would write, including the replacement side of edit lists
    /// (`edits: [{ old_string, new_string }]`).
    private static func content(in object: [String: Any]) -> String? {
        var parts = strings(in: object, keys: contentKeys)
        for key in ["edits", "changes"] {
            guard let edits = object[key] as? [Any] else { continue }
            for edit in edits {
                guard let edit = edit as? [String: Any] else { continue }
                parts.append(contentsOf: strings(in: edit, keys: contentKeys))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static let replacedTextKeys = [
        "old_string", "oldString", "old_source", "oldSource",
    ]

    /// Text the tool replaces, kept as separate entries so that each edit in a
    /// list is matched against the file on its own.
    private static func replacedTexts(in object: [String: Any]) -> [String] {
        var parts = strings(in: object, keys: replacedTextKeys)
        for key in ["edits", "changes"] {
            guard let edits = object[key] as? [Any] else { continue }
            for edit in edits {
                guard let edit = edit as? [String: Any] else { continue }
                parts.append(contentsOf: strings(in: edit, keys: replacedTextKeys))
            }
        }
        return parts
    }

    /// Every path-shaped string in the payload, for tool inputs whose key names
    /// we do not recognize.
    private static func pathLikeValues(in object: [String: Any]) -> [String] {
        var found: [String] = []
        collectPathLikeValues(object, key: nil, into: &found)
        return found
    }

    private static func collectPathLikeValues(_ value: Any, key: String?, into found: inout [String]) {
        if let object = value as? [String: Any] {
            for (nestedKey, nested) in object.sorted(by: { $0.key < $1.key })
            where !envelopeKeys.contains(nestedKey) && !contentKeys.contains(nestedKey) {
                collectPathLikeValues(nested, key: nestedKey, into: &found)
            }
            return
        }
        if let array = value as? [Any] {
            for element in array {
                collectPathLikeValues(element, key: key, into: &found)
            }
            return
        }
        if let text = value as? String, isPathLike(text) {
            found.append(text)
        }
    }

    /// Conservative shape test: a single line naming a file, not prose or a URL.
    private static func isPathLike(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 4096,
              !value.contains("\n"), !value.contains("://") else {
            return false
        }
        let name = (value as NSString).lastPathComponent
        return value.contains("/") || value.hasPrefix(".") || name.contains(".")
    }
}

public enum PromptWriteGateRenderer {
    public static func render(
        decision: PromptWriteGateDecision,
        adapter: CheckHookAdapter
    ) -> CheckHookAdapterOutput {
        switch adapter {
        case .cursor:
            if decision.permission == .allow {
                return CheckHookAdapterOutput(
                    stdout: CheckHookResponseRenderer.encodeJSONObject(["permission": "allow"]),
                    stderr: "",
                    exitCode: 0
                )
            }
            // Cursor accepts `ask` in the `preToolUse` schema but does not enforce
            // it, so rendering ask verbatim would let the write through unnoticed.
            let reason = decision.permission == .ask
                ? decision.reason + " Cursor cannot ask for confirmation on this event, so it is blocked instead."
                : decision.reason
            return CheckHookAdapterOutput(
                stdout: CheckHookResponseRenderer.encodeJSONObject([
                    "permission": "deny",
                    "user_message": reason,
                    "agent_message": reason,
                ]),
                stderr: reason + "\n",
                exitCode: 0
            )
        case .claude:
            if decision.permission == .allow {
                return CheckHookAdapterOutput(stdout: "{}", stderr: "", exitCode: 0)
            }
            return CheckHookAdapterOutput(
                stdout: CheckHookResponseRenderer.encodeJSONObject([
                    "hookSpecificOutput": [
                        "hookEventName": "PreToolUse",
                        "permissionDecision": decision.permission.rawValue,
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
}
