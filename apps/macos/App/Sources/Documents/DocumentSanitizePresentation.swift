import AppUIKit
import DetectionCore
import RiskScoringCore

enum DocumentSanitizePresentation {
    static func uiRisk(for assessment: RiskAssessment) -> OFRiskLevel {
        if assessment.hasCriticalSecret { return .critical }
        switch assessment.level {
        case .low:
            return .none
        case .medium, .high:
            return .medium
        case .critical:
            return .critical
        }
    }

    static func severityBadgeStyle(for type: SensitiveEntityType) -> OFStatusBadgeStyle {
        if type.countsAsCriticalSecret { return .fail }
        if type.isSecret { return .warn }
        return .info
    }
}
