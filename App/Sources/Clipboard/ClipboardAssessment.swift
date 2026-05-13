import DetectionCore
import Foundation
import RiskScoringCore

enum ClipboardAssessmentStatus {
    case idle
    case safe
    case warning
    case risk
}

struct ClipboardAssessmentSnapshot {
    let text: String
    let detection: DetectionResult
    let assessment: RiskAssessment

    var hasRisk: Bool {
        !detection.entities.isEmpty && assessment.recommendedAction != .allow
    }
}
