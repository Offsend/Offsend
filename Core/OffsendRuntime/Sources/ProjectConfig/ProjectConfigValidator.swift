import DetectionCore
import Foundation
import Yams

/// Surfaces values that `OptionsResolver` would silently drop (typos in detector
/// IDs, dictionary kinds, or enum-backed settings) so `offsend doctor` can warn about them.
public enum ProjectConfigValidator {
    public static func validateYAMLStructure(_ contents: String) -> [String] {
        guard let root = try? Yams.load(yaml: contents) as? [String: Any] else {
            return []
        }

        var issues: [String] = []
        issues.append(contentsOf: unknownKeys(in: root, allowed: ["version", "check", "hooks", "context"], path: "root"))

        if let check = root["check"] as? [String: Any] {
            issues.append(
                contentsOf: unknownKeys(
                    in: check,
                    allowed: ["fail_on", "policy", "exclude", "detectors", "dictionaries"],
                    path: "check"
                )
            )

            if check["disable"] != nil {
                issues.append("check.disable is ignored; use check.detectors.disable instead.")
            }

            if let detectors = check["detectors"] as? [String: Any] {
                issues.append(
                    contentsOf: unknownKeys(
                        in: detectors,
                        allowed: ["disable"],
                        path: "check.detectors"
                    )
                )
            }
        }

        if let hooks = root["hooks"] as? [String: Any] {
            issues.append(
                contentsOf: unknownKeys(
                    in: hooks,
                    allowed: ["type", "fail_on", "policy"],
                    path: "hooks"
                )
            )
        }

        if let context = root["context"] as? [String: Any] {
            issues.append(
                contentsOf: unknownKeys(
                    in: context,
                    allowed: ["mcp", "subagents", "history"],
                    path: "context"
                )
            )
            if let mcp = context["mcp"] as? [String: Any] {
                issues.append(
                    contentsOf: unknownKeys(
                        in: mcp,
                        allowed: ["mode", "allow", "deny", "high_risk"],
                        path: "context.mcp"
                    )
                )
            }
            if let subagents = context["subagents"] as? [String: Any] {
                issues.append(
                    contentsOf: unknownKeys(
                        in: subagents,
                        allowed: ["mode", "scan_task"],
                        path: "context.subagents"
                    )
                )
            }
            if let history = context["history"] as? [String: Any] {
                issues.append(
                    contentsOf: unknownKeys(
                        in: history,
                        allowed: ["audit", "scrub_on_protect"],
                        path: "context.history"
                    )
                )
            }
        }

        return issues
    }

    public static func validate(_ config: OffsendProjectConfig) -> [String] {
        var issues: [String] = []

        if let failOn = config.check?.failOn, CheckFailPolicy(rawValue: failOn) == nil {
            issues.append("check.fail_on '\(failOn)' is invalid (use \(validValues(CheckFailPolicy.self))).")
        }

        if let hookFailOn = config.hooks?.failOn, CheckFailPolicy(rawValue: hookFailOn) == nil {
            issues.append("hooks.fail_on '\(hookFailOn)' is invalid (use \(validValues(CheckFailPolicy.self))).")
        }

        if let hookType = config.hooks?.type, HookType(rawValue: hookType) == nil {
            issues.append("hooks.type '\(hookType)' is invalid (use \(validValues(HookType.self))).")
        }

        let unknownDetectors = (config.check?.detectors?.disable ?? [])
            .filter { SensitiveEntityType(rawValue: $0) == nil }
        if !unknownDetectors.isEmpty {
            issues.append("Unknown detector ID(s) in check.detectors.disable: \(unknownDetectors.joined(separator: ", ")).")
        }

        let unknownKinds = (config.check?.dictionaries ?? [])
            .map(\.kind)
            .filter { CustomDictionaryKind(rawValue: $0) == nil }
        if !unknownKinds.isEmpty {
            issues.append("Unknown dictionary kind(s) in check.dictionaries: \(unknownKinds.joined(separator: ", ")).")
        }

        if let mcpMode = config.context?.mcp?.mode,
           OffsendContextEnforcementMode(rawValue: mcpMode) == nil {
            issues.append(
                "context.mcp.mode '\(mcpMode)' is invalid (use \(validValues(OffsendContextEnforcementMode.self)))."
            )
        }

        if let subagentMode = config.context?.subagents?.mode,
           OffsendContextEnforcementMode(rawValue: subagentMode) == nil {
            issues.append(
                "context.subagents.mode '\(subagentMode)' is invalid (use \(validValues(OffsendContextEnforcementMode.self)))."
            )
        }

        return issues
    }

    private static func validValues<T: RawRepresentable & CaseIterable>(_ type: T.Type) -> String where T.RawValue == String {
        T.allCases.map(\.rawValue).joined(separator: ", ")
    }

    private static func unknownKeys(in dictionary: [String: Any], allowed: Set<String>, path: String) -> [String] {
        dictionary.keys
            .filter { !allowed.contains($0) }
            .sorted()
            .map { "Unknown \(path) key '\($0)'." }
    }
}
