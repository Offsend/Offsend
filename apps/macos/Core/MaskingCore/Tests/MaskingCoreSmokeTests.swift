import DetectionCore
import MaskingCore
import XCTest

final class MaskingCoreSmokeTests: XCTestCase {
    func testMappingTTLFreeTier() {
        XCTAssertEqual(MappingTTL.freeTierOptions, [.oneHour])
    }

    func testExcludingTokenSpansDropsPhoneAndEntropyInsideSeal() {
        let text = "{{EMAIL:v1.xx-123-456-7890}}"
        let phoneRange = text.range(of: "123-456-7890")!
        let phone = SensitiveEntity(
            type: .phone,
            range: phoneRange,
            value: String(text[phoneRange]),
            confidence: 0.9,
            source: .regex
        )
        let entropyRange = text.range(of: "xx-123-456-7890")!
        let entropy = SensitiveEntity(
            type: .highEntropyString,
            range: entropyRange,
            value: String(text[entropyRange]),
            confidence: 0.8,
            source: .secret
        )
        let kept = SealTokenDetector.excludingTokenSpans([phone, entropy], in: text)
        XCTAssertTrue(kept.isEmpty)
    }

    func testExcludingTokenSpansKeepsCriticalSecretInsideFakeSeal() {
        let text = "{{FAKE:v1.AKIAABCDEFGHIJ012345}}"
        let range = text.range(of: "AKIAABCDEFGHIJ012345")!
        let aws = SensitiveEntity(
            type: .awsAccessKeyId,
            range: range,
            value: String(text[range]),
            confidence: 1.0,
            source: .secret
        )
        let kept = SealTokenDetector.excludingTokenSpans([aws], in: text)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.type, .awsAccessKeyId)
    }
}
