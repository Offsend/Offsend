import Foundation

/// One shell command that already ran, with the output the editor captured.
public struct PromptShellAuditInput: Equatable, Sendable {
    public let command: String
    public let output: String
    /// True when `output` was cut at the scan limit.
    public let truncated: Bool
    /// `sandbox` as reported by the editor; nil when the editor does not say.
    public let sandboxed: Bool?

    public init(command: String, output: String, truncated: Bool = false, sandboxed: Bool? = nil) {
        self.command = command
        self.output = output
        self.truncated = truncated
        self.sandboxed = sandboxed
    }
}

public struct PromptShellAuditDecision: Equatable, Sendable {
    public let input: PromptShellAuditInput
    public let secretTypes: [String]
    public let reason: String

    public var hasFindings: Bool { !secretTypes.isEmpty }

    public init(input: PromptShellAuditInput, secretTypes: [String], reason: String) {
        self.input = input
        self.secretTypes = secretTypes
        self.reason = reason
    }
}

/// Observational gate for Cursor `afterShellExecution` and Claude `PostToolUse`
/// (Bash): scans what a shell command printed and reports secrets found there.
///
/// This is **a rotation signal and an audit trail, not prevention.** It runs after
/// the command, and neither editor lets a shell hook rewrite terminal output, so
/// by the time this fires the value is already in the model's context. The only
/// honest promise is that the user learns which credential to rotate. Anyone who
/// needs the leak not to happen wants `sandbox.enabled` (egress denial) or the
/// editor's own command allowlist, not this gate.
public enum PromptShellAuditGate {
    /// Output beyond this is not scanned. A build log can be megabytes, and a
    /// post-hoc audit is not worth stalling the agent loop over.
    public static let maxOutputBytes = 256 * 1024

    public static func parse(
        json: String,
        adapter: CheckHookAdapter
    ) throws -> PromptShellAuditInput {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        let input: PromptShellAuditInput?
        switch adapter {
        case .cursor:
            input = extractCursor(from: root)
        case .claude:
            input = extractClaude(from: root)
        case .windsurf, .codex:
            input = nil
        }
        guard let input else { throw PromptHookInputError.invalidJSON }
        return input
    }

    public static func evaluate(
        input: PromptShellAuditInput,
        secretTypes: [String]
    ) -> PromptShellAuditDecision {
        guard !secretTypes.isEmpty else {
            return PromptShellAuditDecision(input: input, secretTypes: [], reason: "")
        }
        var reason = "Offsend: shell output contains secrets "
            + "(\(secretTypes.joined(separator: ", "))). "
            + "They are already in the agent context — rotate them."
        if input.truncated {
            reason += " Only the first \(maxOutputBytes / 1024) KB of output was scanned."
        }
        return PromptShellAuditDecision(
            input: input,
            secretTypes: secretTypes,
            reason: reason
        )
    }

    // MARK: - Extraction

    /// Cursor `afterShellExecution`: `{command, output, duration, sandbox}`.
    private static func extractCursor(from root: [String: Any]) -> PromptShellAuditInput? {
        guard let command = root["command"] as? String, !command.isEmpty else { return nil }
        let bounded = bounded(root["output"] as? String ?? "")
        return PromptShellAuditInput(
            command: command,
            output: bounded.text,
            truncated: bounded.truncated,
            sandboxed: root["sandbox"] as? Bool
        )
    }

    /// Claude `PostToolUse` with the `Bash` matcher.
    private static func extractClaude(from root: [String: Any]) -> PromptShellAuditInput? {
        let toolName = (root["tool_name"] as? String) ?? (root["toolName"] as? String) ?? ""
        guard toolName.isEmpty || toolName == "Bash" else { return nil }
        let toolInput = root["tool_input"] as? [String: Any] ?? [:]
        guard let command = (toolInput["command"] as? String) ?? (root["command"] as? String),
              !command.isEmpty else {
            return nil
        }
        let response = root["tool_response"] ?? root["toolResponse"]
        let bounded = bounded(serialize(response))
        return PromptShellAuditInput(
            command: command,
            output: bounded.text,
            truncated: bounded.truncated,
            sandboxed: root["sandbox"] as? Bool
        )
    }

    private static func serialize(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private static func bounded(_ text: String) -> (text: String, truncated: Bool) {
        guard text.utf8.count > maxOutputBytes else { return (text, false) }
        var end = text.startIndex
        var bytes = 0
        while end < text.endIndex {
            let next = text.index(after: end)
            let characterBytes = text[end..<next].utf8.count
            if bytes + characterBytes > maxOutputBytes { break }
            bytes += characterBytes
            end = next
        }
        return (String(text[..<end]), true)
    }
}

public enum PromptShellAuditGateRenderer {
    /// Neither editor accepts a replacement for terminal output, so the response
    /// is always empty. The finding travels by notification and local log, and
    /// the exit code stays 0 so a finding never looks like a hook failure.
    public static func render(
        decision: PromptShellAuditDecision,
        adapter: CheckHookAdapter
    ) -> CheckHookAdapterOutput {
        let stderr = decision.hasFindings ? decision.reason + "\n" : ""
        switch adapter {
        case .cursor, .claude:
            return CheckHookAdapterOutput(stdout: "{}", stderr: stderr, exitCode: 0)
        case .windsurf, .codex:
            return CheckHookAdapterOutput(stdout: "", stderr: stderr, exitCode: 0)
        }
    }
}
