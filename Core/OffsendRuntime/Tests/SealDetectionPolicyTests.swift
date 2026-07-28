import DetectionCore
import XCTest
@testable import OffsendRuntime

final class SealDetectionPolicyTests: XCTestCase {
    func testSealScanIgnoresConfiguredDisableList() {
        let disabled: Set<SensitiveEntityType> = [
            .email, .url, .openAIAPIKey, .databaseURLWithPassword, .governmentId,
        ]
        XCTAssertTrue(
            SealDetectionPolicy.effectiveDisabledDetectors(disabled).isEmpty
        )
    }

    func testSealEntitiesIncludePIIAndCredentialsButNotFuzzyEntropy() {
        let text = "email token entropy"
        let emailRange = text.startIndex..<text.index(text.startIndex, offsetBy: 5)
        let tokenStart = text.index(text.startIndex, offsetBy: 6)
        let tokenRange = tokenStart..<text.index(tokenStart, offsetBy: 5)
        let entropyStart = text.index(text.startIndex, offsetBy: 12)
        let entropyRange = entropyStart..<text.endIndex
        let entities = [
            SensitiveEntity(
                type: .email,
                range: emailRange,
                value: String(text[emailRange]),
                confidence: 0.9,
                source: .regex
            ),
            SensitiveEntity(
                type: .openAIAPIKey,
                range: tokenRange,
                value: String(text[tokenRange]),
                confidence: 0.99,
                source: .secret
            ),
            SensitiveEntity(
                type: .highEntropyString,
                range: entropyRange,
                value: String(text[entropyRange]),
                confidence: 0.65,
                source: .secret
            ),
        ]

        XCTAssertEqual(
            SealDetectionPolicy.entitiesForSeal(entities).map(\.type),
            [.email, .openAIAPIKey]
        )
    }

    func testSealOverrideFindsDatabaseURLAndEmail() async {
        let text = """
        DATABASE_URL=postgres://demo:SuperSecretPass123@db.prod.internal:5432/app
        owner=security-team@corp.test
        """
        let context = OffsendRuntimeContext(settings: .default, customDictionaries: [])
        let service = OffsendCheckService(context: context)

        let ordinary = await service.runText(
            text,
            failPolicy: .block,
            disabledDetectors: [.databaseURLWithPassword, .url, .email]
        )
        XCTAssertFalse(ordinary.entities.contains { $0.type == .databaseURLWithPassword })
        XCTAssertFalse(ordinary.entities.contains { $0.type == .email })

        let sealedScan = await service.runText(
            text,
            failPolicy: .block,
            disabledDetectors: SealDetectionPolicy.effectiveDisabledDetectors(
                [.databaseURLWithPassword, .url, .email]
            )
        )
        XCTAssertTrue(sealedScan.entities.contains { $0.type == .databaseURLWithPassword })
        XCTAssertTrue(sealedScan.entities.contains { $0.type == .email })
    }
}
