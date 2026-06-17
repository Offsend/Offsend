import DetectionCore
import Foundation

public struct RiskAssessment: Equatable, Sendable {
    public let score: Int
    public let level: RiskLevel
    public let recommendedAction: RecommendedAction
    public let hasCriticalSecret: Bool

    public init(score: Int, level: RiskLevel, recommendedAction: RecommendedAction, hasCriticalSecret: Bool) {
        self.score = score
        self.level = level
        self.recommendedAction = recommendedAction
        self.hasCriticalSecret = hasCriticalSecret
    }
}

public protocol RiskScoring: Sendable {
    func assess(_ entities: [SensitiveEntity], context: DetectionContext) -> RiskAssessment
}

public extension RiskScoring {
    /// Convenience for callers without file-location context (e.g. clipboard scans).
    func assess(_ entities: [SensitiveEntity]) -> RiskAssessment {
        assess(entities, context: .neutral)
    }
}

public final class RiskScoringEngine: RiskScoring {
    /// Upper bound for displayed risk when no confirmed secrets (keys, JWT, etc.) are present.
    public static let nonSecretScoreCap = 75

    public init() {}

    public func assess(_ entities: [SensitiveEntity], context: DetectionContext = .neutral) -> RiskAssessment {
        guard !entities.isEmpty else {
            return RiskAssessment(score: 0, level: .low, recommendedAction: .allow, hasCriticalSecret: false)
        }

        let rawScore = entities.reduce(0) { $0 + Self.weight(for: $1.type) }
        let hasConfirmedSecret = entities.contains { $0.type.countsAsCriticalSecret }

        if hasConfirmedSecret {
            // Confirmed secrets always block; a key in a README or test file is still a leaked key.
            return RiskAssessment(
                score: max(rawScore, 100),
                level: .critical,
                recommendedAction: .block,
                hasCriticalSecret: true
            )
        }

        switch context.sensitivity {
        case .neutral:
            return Self.nonSecretAssessment(score: min(rawScore, Self.nonSecretScoreCap))
        case .secretsConfig:
            // Raise: keep the uncapped score and bump non-secret PII one severity step.
            return Self.escalated(Self.nonSecretAssessment(score: rawScore))
        case .docsOrTests:
            // Lower noise: cap non-secret PII at `warn` (placeholders/sample data are rarely actionable).
            return Self.cappedAtWarn(Self.nonSecretAssessment(score: min(rawScore, Self.nonSecretScoreCap)))
        }
    }

    private static func nonSecretAssessment(score: Int) -> RiskAssessment {
        switch score {
        case 0...19:
            return RiskAssessment(score: score, level: .low, recommendedAction: .allow, hasCriticalSecret: false)
        case 20...49:
            return RiskAssessment(score: score, level: .medium, recommendedAction: .warn, hasCriticalSecret: false)
        default:
            return RiskAssessment(score: score, level: .high, recommendedAction: .mask, hasCriticalSecret: false)
        }
    }

    private static func escalated(_ base: RiskAssessment) -> RiskAssessment {
        switch base.level {
        case .low:
            return RiskAssessment(score: base.score, level: .medium, recommendedAction: .warn, hasCriticalSecret: false)
        case .medium:
            return RiskAssessment(score: base.score, level: .high, recommendedAction: .mask, hasCriticalSecret: false)
        case .high:
            return RiskAssessment(score: base.score, level: .critical, recommendedAction: .block, hasCriticalSecret: false)
        case .critical:
            return base
        }
    }

    private static func cappedAtWarn(_ base: RiskAssessment) -> RiskAssessment {
        switch base.recommendedAction {
        case .mask, .block:
            return RiskAssessment(score: base.score, level: .medium, recommendedAction: .warn, hasCriticalSecret: base.hasCriticalSecret)
        case .allow, .warn:
            return base
        }
    }

    public static func weight(for type: SensitiveEntityType) -> Int {
        switch type {
        case .email, .phone, .money, .invoiceId:
            return 20
        case .url:
            return 10
        case .ipAddress:
            return 15
        case .internalDomain:
            return 35
        case .contractId, .orderId:
            return 25
        case .customClient, .customCompany, .customProject, .customSensitiveTerm, .customInternalDomain:
            return 40
        case .creditCardLike:
            return 80
        case .iban:
            return 60
        case .personName, .streetAddress, .governmentId:
            return 25
        case .jwt:
            return 80
        case .apiKeyGeneric, .openAIAPIKey, .awsAccessKeyId, .githubToken, .slackToken,
             .stripeKey, .privateKey, .sshPrivateKey, .databaseURLWithPassword,
             .bearerToken:
            return 100
        case .highEntropyString:
            return 55
        }
    }
}
