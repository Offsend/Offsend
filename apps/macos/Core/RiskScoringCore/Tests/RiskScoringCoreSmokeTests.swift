import DetectionCore
import RiskScoringCore
import XCTest

final class RiskScoringCoreSmokeTests: XCTestCase {
    func testEmptyAssessmentViaStub() {
        struct AllowAll: RiskScoring {
            func assess(_ entities: [SensitiveEntity], context: DetectionContext) -> RiskAssessment {
                RiskAssessment(score: 0, level: .low, recommendedAction: .allow, hasCriticalSecret: false)
            }
        }
        let assessment = AllowAll().assess([])
        XCTAssertEqual(assessment.level, .low)
    }
}
