import DetectionCore
import XCTest
@testable import MaskingCore

final class MaskingEngineTests: XCTestCase {
    private let engine = MaskingEngine()

    func testGeneratesTypedPlaceholdersAndMapping() {
        let text = "Email ivan@acme.com about CN-4812"
        let entities = [
            entity(.email, "ivan@acme.com", in: text),
            entity(.contractId, "CN-4812", in: text)
        ]

        let result = engine.mask(text: text, entities: entities, ttl: .sixHours)

        XCTAssertEqual(result.maskedText, "Email {{EMAIL_1}} about {{CONTRACT_1}}")
        XCTAssertEqual(result.mapping["{{EMAIL_1}}"], "ivan@acme.com")
        XCTAssertEqual(result.mapping["{{CONTRACT_1}}"], "CN-4812")
        XCTAssertNotNil(result.expiresAt)
    }

    func testPreservesOrderWhenReplacingMultipleEntities() {
        let text = "a@b.com and c@d.com"
        let result = engine.mask(text: text, entities: [
            entity(.email, "a@b.com", in: text),
            entity(.email, "c@d.com", in: text)
        ], ttl: .oneHour)

        XCTAssertEqual(result.maskedText, "{{EMAIL_1}} and {{EMAIL_2}}")
    }

    func testRestoreMapping() {
        let restored = engine.restore(
            text: "Hello {{CLIENT_1}}, email {{EMAIL_1}}",
            mapping: ["{{CLIENT_1}}": "Acme Corp", "{{EMAIL_1}}": "ivan@acme.com"]
        )

        XCTAssertEqual(restored, "Hello Acme Corp, email ivan@acme.com")
    }

    func testNeverStoreHasNoExpiration() {
        let text = "secret sk-abcdefghijklmnopqrstuvwxyzABCDEF123456"
        let result = engine.mask(text: text, entities: [entity(.openAIAPIKey, "sk-abcdefghijklmnopqrstuvwxyzABCDEF123456", in: text)], ttl: .neverStore)

        XCTAssertNil(result.expiresAt)
        XCTAssertFalse(result.shouldPersist)
        XCTAssertEqual(result.retention, .ephemeral)
    }

    func testExpiringTTLIsPersistable() {
        let text = "Email ivan@acme.com"
        let result = engine.mask(text: text, entities: [entity(.email, "ivan@acme.com", in: text)], ttl: .oneHour)

        XCTAssertNotNil(result.expiresAt)
        XCTAssertTrue(result.shouldPersist)
    }

    func testIdenticalValuesShareSinglePlaceholder() {
        let text = "ivan@acme.com and ivan@acme.com"
        let result = engine.mask(text: text, entities: [
            entity(.email, "ivan@acme.com", in: text),
            lastEntity(.email, "ivan@acme.com", in: text)
        ], ttl: .oneHour)

        XCTAssertEqual(result.maskedText, "{{EMAIL_1}} and {{EMAIL_1}}")
        XCTAssertEqual(result.mapping, ["{{EMAIL_1}}": "ivan@acme.com"])
    }

    func testSkipsOverlappingRanges() {
        let text = "ivan@acme.com"
        let full = entity(.email, "ivan@acme.com", in: text)
        let overlapping = SensitiveEntity(
            type: .customCompany,
            range: text.startIndex..<text.index(text.startIndex, offsetBy: 4),
            value: "ivan",
            confidence: 1,
            source: .customDictionary
        )

        let result = engine.mask(text: text, entities: [full, overlapping], ttl: .oneHour)

        XCTAssertEqual(result.maskedText, "{{EMAIL_1}}")
        XCTAssertEqual(result.mapping, ["{{EMAIL_1}}": "ivan@acme.com"])
    }

    func testSkipsEntitiesWhoseRangeDoesNotMatchText() {
        let source = "Email ivan@acme.com"
        let stale = entity(.email, "ivan@acme.com", in: source)
        let differentText = "Hi"

        let result = engine.mask(text: differentText, entities: [stale], ttl: .oneHour)

        XCTAssertEqual(result.maskedText, differentText)
        XCTAssertTrue(result.mapping.isEmpty)
    }

    func testMappingTTLOptionsRespectTariff() {
        XCTAssertEqual(MappingTTL.allowedOptions(extendedTTLAllowed: false), [.oneHour])
        XCTAssertEqual(MappingTTL.allowedOptions(extendedTTLAllowed: true), MappingTTL.allCases)
    }

    func testMappingTTLEffectiveClampsFreeTierSelection() {
        XCTAssertEqual(MappingTTL.effective(.twentyFourHours, extendedTTLAllowed: false), .oneHour)
        XCTAssertEqual(MappingTTL.effective(.twentyFourHours, extendedTTLAllowed: true), .twentyFourHours)
    }

    private func entity(_ type: SensitiveEntityType, _ value: String, in text: String) -> SensitiveEntity {
        guard let range = text.range(of: value) else {
            XCTFail("Missing test value \(value)")
            return SensitiveEntity(type: type, range: text.startIndex..<text.startIndex, value: "", confidence: 0, source: .regex)
        }
        return SensitiveEntity(type: type, range: range, value: value, confidence: 1, source: type.isSecret ? .secret : .regex)
    }

    private func lastEntity(_ type: SensitiveEntityType, _ value: String, in text: String) -> SensitiveEntity {
        guard let range = text.range(of: value, options: .backwards) else {
            XCTFail("Missing test value \(value)")
            return SensitiveEntity(type: type, range: text.startIndex..<text.startIndex, value: "", confidence: 0, source: .regex)
        }
        return SensitiveEntity(type: type, range: range, value: value, confidence: 1, source: type.isSecret ? .secret : .regex)
    }
}
