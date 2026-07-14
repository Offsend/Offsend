import DetectionCore
import Foundation

public struct PromptCheckAdviceFinding: Equatable, Sendable {
    public let type: SensitiveEntityType
    /// Type label only — never includes secret material.
    public let fingerprint: String
    public let remediation: CheckRemediation
    public let message: String

    public init(
        type: SensitiveEntityType,
        fingerprint: String,
        remediation: CheckRemediation,
        message: String
    ) {
        self.type = type
        self.fingerprint = fingerprint
        self.remediation = remediation
        self.message = message
    }
}

public struct PromptCheckAdviceResult: Equatable, Sendable {
    public let policy: CheckHookPolicy
    public let findings: [PromptCheckAdviceFinding]
    public let userMessage: String
    public let sealedText: String?
    public let sealedCopyPath: String?

    public init(
        policy: CheckHookPolicy,
        findings: [PromptCheckAdviceFinding],
        userMessage: String,
        sealedText: String? = nil,
        sealedCopyPath: String? = nil
    ) {
        self.policy = policy
        self.findings = findings
        self.userMessage = userMessage
        self.sealedText = sealedText
        self.sealedCopyPath = sealedCopyPath
    }

    public var findingCount: Int { findings.count }
    public var hasFindings: Bool { !findings.isEmpty }

    /// Short notification body — no types that embed values, no fingerprints.
    public var notificationBody: String {
        guard hasFindings else { return "Offsend: prompt looks clean." }
        let count = findingCount
        let noun = count == 1 ? "item" : "items"
        return "Offsend: \(count) sensitive \(noun) in prompt — move secrets to env."
    }
}

public enum PromptCheckAdviceBuilder {
    public static func filterEntities(
        _ entities: [SensitiveEntity],
        secretsOnly: Bool
    ) -> [SensitiveEntity] {
        guard secretsOnly else { return entities }
        // highEntropyString is too noisy for default soft-block; opt in via --no-secrets-only.
        return entities.filter { $0.type.isSecret && $0.type != .highEntropyString }
    }

    public static func build(
        entities: [SensitiveEntity],
        policy: CheckHookPolicy,
        sealedText: String? = nil,
        sealedCopyPath: String? = nil,
        secretsOnly: Bool = true,
        attachmentAdviceLines: [String] = [],
        sealAttempted: Bool = false
    ) -> PromptCheckAdviceResult {
        let filtered = filterEntities(entities, secretsOnly: secretsOnly)
        var findings = filtered.map { entity -> PromptCheckAdviceFinding in
            let remediation = remediation(for: entity.type)
            let fingerprint = fingerprint(for: entity.type)
            return PromptCheckAdviceFinding(
                type: entity.type,
                fingerprint: fingerprint,
                remediation: remediation,
                message: message(for: entity.type, remediation: remediation)
            )
        }
        for line in attachmentAdviceLines {
            findings.append(
                PromptCheckAdviceFinding(
                    type: .customSensitiveTerm,
                    fingerprint: "attachment",
                    remediation: .addToIgnore,
                    message: line
                )
            )
        }

        var userMessage: String
        if findings.isEmpty {
            userMessage = "Offsend: no sensitive data detected in prompt."
        } else {
            let count = findings.count
            let noun = count == 1 ? "fragment" : "fragments"
            userMessage =
                "Offsend: prompt contains \(count) sensitive \(noun). "
                + "Move secrets to env / ignore files and avoid pasting values into chat."
            if policy == .block {
                if sealedCopyPath != nil || sealedText != nil {
                    userMessage += " Prompt blocked; sealed copy is on the clipboard."
                } else if sealAttempted {
                    userMessage += " Prompt blocked; seal unavailable — run: offsend keygen -o ~/.offsend/seal.key"
                } else {
                    userMessage += " Prompt blocked (same as soft-block)."
                }
            }
        }

        return PromptCheckAdviceResult(
            policy: policy,
            findings: findings,
            userMessage: userMessage,
            sealedText: sealedText,
            sealedCopyPath: sealedCopyPath
        )
    }

    public static func remediation(for type: SensitiveEntityType) -> CheckRemediation {
        switch type {
        case .privateKey, .sshPrivateKey:
            return .addToIgnore
        case .apiKeyGeneric, .openAIAPIKey, .awsAccessKeyId, .githubToken, .slackToken,
             .stripeKey, .jwt, .databaseURLWithPassword, .bearerToken, .highEntropyString:
            return .moveToEnv
        default:
            return .dontPaste
        }
    }

    /// Public label only — never derived from secret bytes.
    public static func fingerprint(for type: SensitiveEntityType) -> String {
        type.rawValue
    }

    @available(*, deprecated, message: "Use fingerprint(for:) — value-based fingerprints leak secret material.")
    public static func fingerprint(_ value: String) -> String {
        _ = value
        return "redacted"
    }

    public static func message(
        for type: SensitiveEntityType,
        remediation: CheckRemediation
    ) -> String {
        let label = type.rawValue
        switch remediation {
        case .moveToEnv:
            return "\(label): move to .env / secret manager; reference the variable name in the prompt."
        case .addToIgnore:
            return "\(label): do not paste key material; keep files in AI ignore (`offsend prepare`)."
        case .dontPaste:
            return "\(label): avoid pasting this value; describe the need without the secret/PII."
        }
    }

    public static func detailLines(for result: PromptCheckAdviceResult) -> [String] {
        result.findings.map(\.message)
    }
}
