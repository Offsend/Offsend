import DetectionCore
import Foundation

public struct RiskAssessment: Equatable {
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
    func assess(_ entities: [SensitiveEntity]) -> RiskAssessment
}

public final class RiskScoringEngine: RiskScoring {
    /// Upper bound for displayed risk when no confirmed secrets (keys, JWT, etc.) are present.
    public static let nonSecretScoreCap = 75

    public init() {}

    public func assess(_ entities: [SensitiveEntity]) -> RiskAssessment {
        let rawScore = entities.reduce(0) { $0 + Self.weight(for: $1.type) }
        let hasConfirmedSecret = entities.contains { $0.type.countsAsCriticalSecret }

        if hasConfirmedSecret {
            return RiskAssessment(
                score: max(rawScore, 100),
                level: .critical,
                recommendedAction: .block,
                hasCriticalSecret: true
            )
        }

        let score = min(rawScore, Self.nonSecretScoreCap)

        switch score {
        case 0...19:
            return RiskAssessment(score: score, level: .low, recommendedAction: .allow, hasCriticalSecret: false)
        case 20...49:
            return RiskAssessment(score: score, level: .medium, recommendedAction: .warn, hasCriticalSecret: false)
        default:
            return RiskAssessment(score: score, level: .high, recommendedAction: .mask, hasCriticalSecret: false)
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
