import DetectionCore
import Foundation

public enum PromptSubagentGatePermission: String, Equatable, Sendable {
    case allow
    case deny
}

public struct PromptSubagentGateCall: Equatable, Sendable {
    public let task: String
    public let subagentType: String?

    public init(task: String, subagentType: String? = nil) {
        self.task = task
        self.subagentType = subagentType
    }
}

public struct PromptSubagentGateDecision: Equatable, Sendable {
    public let call: PromptSubagentGateCall
    public let permission: PromptSubagentGatePermission
    public let reason: String
    public let code: String
    public let secretTypes: [String]

    public var allowed: Bool { permission == .allow }

    public init(
        call: PromptSubagentGateCall,
        permission: PromptSubagentGatePermission,
        reason: String,
        code: String,
        secretTypes: [String] = []
    ) {
        self.call = call
        self.permission = permission
        self.reason = reason
        self.code = code
        self.secretTypes = secretTypes
    }
}

/// Cursor `subagentStart` gate: secret-scan the task prompt before a subagent is spawned.
/// Cursor does not support `ask` for this event — findings become `deny` unless mode is `observe`.
public enum PromptSubagentGate {
    public static func parse(json: String, adapter: CheckHookAdapter) throws -> PromptSubagentGateCall {
        guard adapter == .cursor else {
            throw PromptHookInputError.invalidJSON
        }
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        guard let call = extractCall(from: root) else {
            throw PromptHookInputError.invalidJSON
        }
        return call
    }

    public static func evaluate(
        call: PromptSubagentGateCall,
        subagentsConfig: OffsendProjectSubagentsConfig? = nil,
        secretTypes: [String] = []
    ) -> PromptSubagentGateDecision {
        let mode = OffsendContextEnforcementMode(rawValue: subagentsConfig?.mode ?? "") ?? .deny
        let scanTask = subagentsConfig?.scanTask ?? true

        guard scanTask else {
            return PromptSubagentGateDecision(
                call: call,
                permission: .allow,
                reason: "",
                code: "allow"
            )
        }

        guard !secretTypes.isEmpty else {
            return PromptSubagentGateDecision(
                call: call,
                permission: .allow,
                reason: "",
                code: "allow"
            )
        }

        let typeList = secretTypes.joined(separator: ", ")
        let reason = "Offsend: subagent task contains secrets (\(typeList))."
        switch mode {
        case .observe:
            return PromptSubagentGateDecision(
                call: call,
                permission: .allow,
                reason: reason,
                code: "secrets",
                secretTypes: secretTypes
            )
        case .ask, .deny:
            // Cursor treats ask as deny for subagentStart; surface an explicit deny.
            return PromptSubagentGateDecision(
                call: call,
                permission: .deny,
                reason: reason,
                code: "secrets",
                secretTypes: secretTypes
            )
        }
    }

    public static func extractCall(from root: [String: Any]) -> PromptSubagentGateCall? {
        let task = (root["task"] as? String)
            ?? (root["prompt"] as? String)
            ?? (root["description"] as? String)
        guard let task, !task.isEmpty else { return nil }
        let subagentType = (root["subagent_type"] as? String)
            ?? (root["subagentType"] as? String)
            ?? (root["type"] as? String)
        return PromptSubagentGateCall(task: task, subagentType: subagentType)
    }
}

public enum PromptSubagentGateRenderer {
    public static func render(
        decision: PromptSubagentGateDecision,
        adapter: CheckHookAdapter
    ) -> CheckHookAdapterOutput {
        switch adapter {
        case .cursor:
            switch decision.permission {
            case .allow:
                var stderr = ""
                if decision.code != "allow", !decision.reason.isEmpty {
                    stderr = decision.reason + "\n"
                }
                return CheckHookAdapterOutput(
                    stdout: CheckHookResponseRenderer.encodeJSONObject(["permission": "allow"]),
                    stderr: stderr,
                    exitCode: 0
                )
            case .deny:
                return CheckHookAdapterOutput(
                    stdout: CheckHookResponseRenderer.encodeJSONObject([
                        "permission": "deny",
                        "user_message": decision.reason,
                    ]),
                    stderr: decision.reason + "\n",
                    exitCode: 0
                )
            }
        case .claude, .windsurf, .codex:
            return CheckHookAdapterOutput(stdout: "", stderr: "", exitCode: 0)
        }
    }
}
