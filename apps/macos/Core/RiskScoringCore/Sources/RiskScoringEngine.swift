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
