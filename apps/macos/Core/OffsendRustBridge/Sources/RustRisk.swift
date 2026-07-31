import DetectionCore
import Foundation
import RiskScoringCore

private struct RustRiskDTO: Decodable {
    let score: Int
    let level: String
    let recommendedAction: String
    let hasCriticalSecret: Bool
}

/// `RiskScoring` backed by Rust `offsend_risk_assess`.
/// FFI is required — there is no Swift `RiskScoringEngine` fallback.
public final class RustRiskScoringEngine: RiskScoring, @unchecked Sendable {
    public init() {}

    public func assess(_ entities: [SensitiveEntity], context: DetectionContext) -> RiskAssessment {
        guard !entities.isEmpty else {
            return RiskAssessment(score: 0, level: .low, recommendedAction: .allow, hasCriticalSecret: false)
        }
        do {
            let types = entities.map(\.type.rawValue)
            let typesData = try JSONEncoder().encode(types)
            guard let typesJSON = String(data: typesData, encoding: .utf8) else {
                throw RustFFIError.invalidUTF8
            }
            let contextName = context.sensitivity.rawValue
            let json = try typesJSON.withCString { cTypes in
                try contextName.withCString { cContext in
                    try RustFFI.call { errOut in
                        offsend_risk_assess(cTypes, cContext, errOut)
                    }
                }
            }
            let dto = try RustFFI.decode(RustRiskDTO.self, from: json)
            guard let level = RiskLevel(rawValue: dto.level),
                  let action = RecommendedAction(rawValue: dto.recommendedAction) else {
                throw RustFFIError.decodingFailed("invalid risk level/action")
            }
            return RiskAssessment(
                score: dto.score,
                level: level,
                recommendedAction: action,
                hasCriticalSecret: dto.hasCriticalSecret
            )
        } catch {
            assertionFailure("Rust risk assess failed: \(error)")
            // Fail closed: treat as critical so paste/sanitize cannot silently allow.
            return RiskAssessment(
                score: 100,
                level: .critical,
                recommendedAction: .block,
                hasCriticalSecret: true
            )
        }
    }
}
