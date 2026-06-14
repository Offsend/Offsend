import DetectionCore
import Foundation

public struct ResolvedCheckOptions: Equatable, Sendable {
    public let failPolicy: CheckFailPolicy
    public let policy: Bool
    public let excludePatterns: [String]
    public let disabledDetectors: Set<SensitiveEntityType>
    public let customDictionaries: [CustomDictionaryItem]

    public init(
        failPolicy: CheckFailPolicy,
        policy: Bool,
        excludePatterns: [String] = [],
        disabledDetectors: Set<SensitiveEntityType> = [],
        customDictionaries: [CustomDictionaryItem] = []
    ) {
        self.failPolicy = failPolicy
        self.policy = policy
        self.excludePatterns = excludePatterns
        self.disabledDetectors = disabledDetectors
        self.customDictionaries = customDictionaries
    }
}

public struct ResolvedHookOptions: Equatable, Sendable {
    public let hookType: HookType
    public let failPolicy: CheckFailPolicy
    public let includePolicyCheck: Bool

    public init(
        hookType: HookType = .preCommit,
        failPolicy: CheckFailPolicy = .block,
        includePolicyCheck: Bool = false
    ) {
        self.hookType = hookType
        self.failPolicy = failPolicy
        self.includePolicyCheck = includePolicyCheck
    }
}

public struct CLICheckOverrides: Sendable {
    public var policySpecified: Bool
    public var policyValue: Bool
    public var failOn: String?

    public init(
        policySpecified: Bool = false,
        policyValue: Bool = false,
        failOn: String? = nil
    ) {
        self.policySpecified = policySpecified
        self.policyValue = policyValue
        self.failOn = failOn
    }
}

public struct CLIHookOverrides: Sendable {
    public var hookType: String?
    public var policySpecified: Bool
    public var policyValue: Bool
    public var failOn: String?

    public init(
        hookType: String? = nil,
        policySpecified: Bool = false,
        policyValue: Bool = false,
        failOn: String? = nil
    ) {
        self.hookType = hookType
        self.policySpecified = policySpecified
        self.policyValue = policyValue
        self.failOn = failOn
    }
}

public enum OptionsResolver {
    public static func resolveCheckOptions(
        overrides: CLICheckOverrides,
        projectConfig: OffsendProjectConfig?,
        staged: Bool
    ) -> ResolvedCheckOptions {
        let checkConfig = projectConfig?.check

        let failPolicy = CheckFailPolicy(rawValue: overrides.failOn ?? checkConfig?.failOn ?? CheckFailPolicy.block.rawValue)
            ?? .block

        let policy: Bool
        if overrides.policySpecified {
            policy = overrides.policyValue
        } else {
            policy = checkConfig?.policy ?? false
        }

        return ResolvedCheckOptions(
            failPolicy: failPolicy,
            policy: policy,
            excludePatterns: checkConfig?.exclude ?? [],
            disabledDetectors: disabledDetectors(from: checkConfig),
            customDictionaries: customDictionaries(from: checkConfig)
        )
    }

    public static func resolveHookOptions(
        overrides: CLIHookOverrides,
        projectConfig: OffsendProjectConfig?
    ) -> ResolvedHookOptions {
        let hookConfig = projectConfig?.hooks
        let checkConfig = projectConfig?.check

        let hookType = HookType(rawValue: overrides.hookType ?? hookConfig?.type ?? HookType.preCommit.rawValue)
            ?? .preCommit

        let failPolicy = CheckFailPolicy(
            rawValue: overrides.failOn ?? hookConfig?.failOn ?? checkConfig?.failOn ?? CheckFailPolicy.block.rawValue
        ) ?? .block

        let includePolicyCheck: Bool
        if overrides.policySpecified {
            includePolicyCheck = overrides.policyValue
        } else {
            includePolicyCheck = hookConfig?.policy ?? checkConfig?.policy ?? false
        }

        return ResolvedHookOptions(
            hookType: hookType,
            failPolicy: failPolicy,
            includePolicyCheck: includePolicyCheck
        )
    }

    public static func defaultsForHookedRepository(from projectConfig: OffsendProjectConfig?) -> (failPolicy: String, includePolicyCheck: Bool) {
        let resolved = resolveHookOptions(overrides: CLIHookOverrides(), projectConfig: projectConfig)
        return (resolved.failPolicy.rawValue, resolved.includePolicyCheck)
    }

    private static func disabledDetectors(from config: OffsendProjectCheckConfig?) -> Set<SensitiveEntityType> {
        guard let rawValues = config?.detectors?.disable else { return [] }
        return Set(rawValues.compactMap { SensitiveEntityType(rawValue: $0) })
    }

    private static func customDictionaries(from config: OffsendProjectCheckConfig?) -> [CustomDictionaryItem] {
        guard let entries = config?.dictionaries else { return [] }
        return entries.compactMap { entry in
            guard let kind = CustomDictionaryKind(rawValue: entry.kind) else { return nil }
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return CustomDictionaryItem(kind: kind, value: value)
        }
    }
}
