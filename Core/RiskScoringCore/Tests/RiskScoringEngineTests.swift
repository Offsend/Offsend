import DetectionCore
import XCTest
@testable import RiskScoringCore

final class RiskScoringEngineTests: XCTestCase {
    private let engine = RiskScoringEngine()

    func testLowRiskAllowsWhenNoEntities() {
        let assessment = engine.assess([])

        XCTAssertEqual(assessment.score, 0)
        XCTAssertEqual(assessment.level, .low)
        XCTAssertEqual(assessment.recommendedAction, .allow)
        XCTAssertFalse(assessment.hasCriticalSecret)
    }

    func testLowRiskAllowsForSingleLowWeightEntity() {
        let assessmentUrl = engine.assess([entity(.url)])

        XCTAssertEqual(assessmentUrl.score, 10)
        XCTAssertEqual(assessmentUrl.level, .low)
        XCTAssertEqual(assessmentUrl.recommendedAction, .allow)

        let assessmentIp = engine.assess([entity(.ipAddress)])

        XCTAssertEqual(assessmentIp.score, 15)
        XCTAssertEqual(assessmentIp.level, .low)
    }

    func testMediumRiskWarnsForSingleEmailWeightTwenty() {
        let assessment = engine.assess([entity(.email)])

        XCTAssertEqual(assessment.score, 20)
        XCTAssertEqual(RiskScoringEngine.weight(for: .email), 20)
        XCTAssertEqual(assessment.level, .medium)
        XCTAssertEqual(assessment.recommendedAction, .warn)
        XCTAssertFalse(assessment.hasCriticalSecret)
    }

    func testHighRiskBoundaryFourUrlsVersusFiveUrls() {
        let four = engine.assess((0..<4).map { _ in entity(.url) })

        XCTAssertEqual(four.score, 40)
        XCTAssertEqual(four.level, .medium)
        XCTAssertEqual(four.recommendedAction, .warn)

        let five = engine.assess((0..<5).map { _ in entity(.url) })

        XCTAssertEqual(five.score, 50)
        XCTAssertEqual(five.level, .high)
        XCTAssertEqual(five.recommendedAction, .mask)
    }

    func testHighRiskMasksMultiplePIIScoreSixty() {
        let assessment = engine.assess([entity(.email), entity(.phone), entity(.money)])

        XCTAssertEqual(assessment.score, 60)
        XCTAssertEqual(assessment.level, .high)
        XCTAssertEqual(assessment.recommendedAction, .mask)
    }

    func testDensePIIWithoutSecretsIsCappedAtSeventyFive() {
        let entities = (
            entity(.contractId),
            entity(.contractId),
            entity(.money),
            entity(.money)
        )
        let assessment = engine.assess([entities.0, entities.1, entities.2, entities.3])

        XCTAssertEqual(RiskScoringEngine.weight(for: .contractId), 25)
        XCTAssertEqual(assessment.score, RiskScoringEngine.nonSecretScoreCap)
        XCTAssertEqual(assessment.level, .high)
        XCTAssertEqual(assessment.recommendedAction, .mask)
        XCTAssertFalse(assessment.hasCriticalSecret)
    }

    func testTypicalInvoicePIIScoresSeventyFiveNotCritical() {
        let assessment = engine.assess([
            entity(.email),
            entity(.phone),
            entity(.contractId),
            entity(.money),
            entity(.url),
        ])

        XCTAssertEqual(assessment.score, 75)
        XCTAssertEqual(assessment.level, .high)
        XCTAssertEqual(assessment.recommendedAction, .mask)
        XCTAssertFalse(assessment.hasCriticalSecret)
    }

    func testCriticalSecretSetsMinimumDisplayedScoreOneHundred() {
        let assessment = engine.assess([entity(.jwt)])

        XCTAssertEqual(RiskScoringEngine.weight(for: .jwt), 80)
        XCTAssertEqual(
            assessment.score,
            max(80, 100),
            "Critical secret: displayed score must not be below 100 when raw sum is lower"
        )
        XCTAssertEqual(assessment.level, .critical)
        XCTAssertEqual(assessment.recommendedAction, .block)
        XCTAssertTrue(assessment.hasCriticalSecret)
    }

    func testCriticalSecretPreservesSumAboveOneHundred() {
        let assessment = engine.assess([
            entity(.url),
            entity(.stripeKey),
        ])

        XCTAssertEqual(RiskScoringEngine.weight(for: .url), 10)
        XCTAssertEqual(RiskScoringEngine.weight(for: .stripeKey), 100)

        XCTAssertEqual(assessment.score, 110)
        XCTAssertEqual(assessment.level, .critical)
        XCTAssertTrue(assessment.hasCriticalSecret)
    }

    func testCriticalSecretOverridesScoreOpenAIOnly() {
        let assessment = engine.assess([entity(.openAIAPIKey)])

        XCTAssertEqual(RiskScoringEngine.weight(for: .openAIAPIKey), 100)
        XCTAssertEqual(assessment.score, 100)
        XCTAssertEqual(assessment.level, .critical)
        XCTAssertEqual(assessment.recommendedAction, .block)
        XCTAssertTrue(assessment.hasCriticalSecret)
    }

    func testHighEntropySecretIsHeuristicNotCriticalCredential() {
        let assessment = engine.assess([entity(.highEntropyString)])

        XCTAssertEqual(assessment.score, 55)
        XCTAssertEqual(RiskScoringEngine.weight(for: .highEntropyString), 55)
        XCTAssertEqual(assessment.level, .high)
        XCTAssertEqual(assessment.recommendedAction, .mask)
        XCTAssertFalse(assessment.hasCriticalSecret)
    }

    func testCustomDictionaryWeightsRaiseRisk() {
        let assessment = engine.assess([entity(.customClient), entity(.contractId)])

        XCTAssertEqual(assessment.score, 65)
        XCTAssertEqual(assessment.level, .high)
    }

    func testWeightIncludesEveryDetectorTypeWithoutDefault() {
        for type in SensitiveEntityType.allCases {
            XCTAssertGreaterThan(RiskScoringEngine.weight(for: type), 0, "Missing risk weight for detector type: \(type)")
        }
    }

    func testRepeatedEntitiesSumWeightsEachOccurrence() {
        let doubled = engine.assess([entity(.email), entity(.email)])

        XCTAssertEqual(doubled.score, 40)
        XCTAssertEqual(doubled.level, .medium)
    }

    private func entity(_ type: SensitiveEntityType) -> SensitiveEntity {
        let text = "value"
        return SensitiveEntity(type: type, range: text.startIndex..<text.endIndex, value: text, confidence: 1, source: .regex)
    }
}
