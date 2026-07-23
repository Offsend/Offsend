#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import DetectionCore
import XCTest
@testable import MaskingCore

final class SealEngineTests: XCTestCase {
    private var key: SymmetricKey!
    private var engine: SealEngine!

    override func setUp() {
        super.setUp()
        key = SymmetricKey(size: .bits256)
        engine = SealEngine(key: key)
    }

    func testRoundTripEmailAndPhone() throws {
        let emailToken = try engine.seal(plaintext: "ivan@acme.com", type: "EMAIL")
        let phoneToken = try engine.seal(plaintext: "+15551234567", type: "PHONE")

        XCTAssertTrue(emailToken.hasPrefix("{{EMAIL:v1."))
        XCTAssertTrue(emailToken.hasSuffix("}}"))
        XCTAssertTrue(phoneToken.hasPrefix("{{PHONE:v1."))

        let email = try engine.open(token: emailToken)
        let phone = try engine.open(token: phoneToken)
        XCTAssertEqual(email.type, "EMAIL")
        XCTAssertEqual(email.plaintext, "ivan@acme.com")
        XCTAssertEqual(phone.type, "PHONE")
        XCTAssertEqual(phone.plaintext, "+15551234567")
    }

    func testDeterministicTokensForSameValueAndType() throws {
        let a = try engine.seal(plaintext: "ivan@acme.com", type: "EMAIL")
        let b = try engine.seal(plaintext: "ivan@acme.com", type: "EMAIL")
        XCTAssertEqual(a, b)
    }

    func testDifferentTypesProduceDifferentTokens() throws {
        let asEmail = try engine.seal(plaintext: "same", type: "EMAIL")
        let asSecret = try engine.seal(plaintext: "same", type: "SECRET")
        XCTAssertNotEqual(asEmail, asSecret)
    }

    func testAADRejectsTypeTampering() throws {
        let token = try engine.seal(plaintext: "ivan@acme.com", type: "EMAIL")
        let tampered = token.replacingOccurrences(of: "{{EMAIL:", with: "{{SECRET:")
        XCTAssertThrowsError(try engine.open(token: tampered)) { error in
            XCTAssertEqual(error as? SealError, .decryptionFailed)
        }
    }

    func testWrongKeyFailsDecryption() throws {
        let token = try engine.seal(plaintext: "ivan@acme.com", type: "EMAIL")
        let other = SealEngine(key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try other.open(token: token)) { error in
            XCTAssertEqual(error as? SealError, .decryptionFailed)
        }
    }

    func testPlaintextOverLimitThrowsOnDirectSeal() {
        let limited = SealEngine(key: key, maxPlaintextBytes: 256)
        let large = String(repeating: "a", count: 257)
        XCTAssertThrowsError(try limited.seal(plaintext: large, type: "SECRET")) { error in
            XCTAssertEqual(
                error as? SealError,
                .plaintextTooLarge(byteCount: 257, limit: 256)
            )
        }
    }

    func testSealTextFailsClosedOnOversizedEntity() {
        let limited = SealEngine(key: key, maxPlaintextBytes: 256)
        let small = "ivan@acme.com"
        let large = String(repeating: "x", count: 300)
        let text = "\(small) \(large)"
        let entities = [
            entity(.email, small, in: text),
            entity(.openAIAPIKey, large, in: text),
        ]

        XCTAssertThrowsError(try limited.seal(text: text, entities: entities)) { error in
            XCTAssertEqual(
                error as? SealError,
                .plaintextTooLarge(byteCount: 300, limit: 256)
            )
        }
    }

    func testSealTextSealsLargeValueWithinRaisedLimit() throws {
        let large = String(repeating: "x", count: 300)
        let text = "secret \(large)"
        let entities = [entity(.openAIAPIKey, large, in: text)]

        let result = try engine.seal(text: text, entities: entities)
        XCTAssertEqual(result.sealedCount, 1)
        XCTAssertFalse(result.sealedText.contains(large))
        XCTAssertTrue(SealTokenDetector.containsSealTokens(in: result.sealedText))
    }

    func testSealTextRoundTripViaUnseal() throws {
        let text = "Email ivan@acme.com about CN-4812"
        let entities = [
            entity(.email, "ivan@acme.com", in: text),
            entity(.contractId, "CN-4812", in: text),
        ]

        let sealed = try engine.seal(text: text, entities: entities)
        XCTAssertEqual(sealed.sealedCount, 2)
        XCTAssertFalse(sealed.sealedText.contains("ivan@acme.com"))
        XCTAssertFalse(sealed.sealedText.contains("CN-4812"))

        let restored = try engine.unseal(text: sealed.sealedText)
        XCTAssertEqual(restored, text)
    }

    func testIdenticalValuesShareDeterministicToken() throws {
        let text = "ivan@acme.com and ivan@acme.com"
        let result = try engine.seal(text: text, entities: [
            entity(.email, "ivan@acme.com", in: text),
            lastEntity(.email, "ivan@acme.com", in: text),
        ])

        let tokens = result.sealedText.components(separatedBy: " and ")
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0], tokens[1])
        XCTAssertEqual(result.sealedCount, 2)
    }

    func testUnsealWithNoTokensReturnsOriginal() throws {
        let text = "nothing sensitive here"
        XCTAssertEqual(try engine.unseal(text: text), text)
    }

    func testSealTokenDetectorFindsTokens() throws {
        let token = try engine.seal(plaintext: "a@b.com", type: "EMAIL")
        XCTAssertTrue(SealTokenDetector.containsSealTokens(in: "hi \(token)"))
        XCTAssertFalse(SealTokenDetector.containsSealTokens(in: "hi {{EMAIL_1}}"))
        XCTAssertEqual(SealTokenDetector.tokenCount(in: "\(token) \(token)"), 2)
    }

    func testExcludingTokenSpansDropsEntitiesInsideTokens() throws {
        let token = try engine.seal(plaintext: "sk-abcdefghijklmnopqrstuvwxyz123456", type: "OPENAI_API_KEY")
        let live = "sk-live0000000000000000000000000000"
        let text = "sealed: \(token) live: \(live)"

        // Detector "fires" on the token payload and on the live value.
        let payloadStart = text.range(of: "v1.")!.upperBound
        let payloadEnd = text.index(payloadStart, offsetBy: 10)
        let insideToken = SensitiveEntity(
            type: .highEntropyString,
            range: payloadStart..<payloadEnd,
            value: String(text[payloadStart..<payloadEnd]),
            confidence: 0.9,
            source: .secret
        )
        let liveRange = text.range(of: live)!
        let liveEntity = SensitiveEntity(
            type: .openAIAPIKey,
            range: liveRange,
            value: live,
            confidence: 0.99,
            source: .secret
        )

        let filtered = SealTokenDetector.excludingTokenSpans([insideToken, liveEntity], in: text)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.value, live)
    }

    func testExcludingTokenSpansKeepsAllWithoutTokens() {
        let text = "no tokens here"
        let range = text.range(of: "tokens")!
        let entity = SensitiveEntity(
            type: .email,
            range: range,
            value: "tokens",
            confidence: 0.5,
            source: .regex
        )
        XCTAssertEqual(SealTokenDetector.excludingTokenSpans([entity], in: text).count, 1)
    }

    func testUnsupportedVersion() throws {
        let token = try engine.seal(plaintext: "a@b.com", type: "EMAIL")
        let broken = token.replacingOccurrences(of: ":v1.", with: ":v2.")
        XCTAssertThrowsError(try engine.open(token: broken)) { error in
            XCTAssertEqual(error as? SealError, .unsupportedTokenVersion("v2"))
        }
    }

    func testInvalidKeyDataLengths() {
        for length in [0, 16, 31, 33] {
            XCTAssertThrowsError(try SealEngine(keyData: Data(repeating: 1, count: length))) { error in
                guard case SealError.invalidKey = error else {
                    return XCTFail("Expected invalidKey for length \(length), got \(error)")
                }
            }
        }
    }

    func testAcceptsExact32ByteKeyData() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let fromData = try SealEngine(keyData: keyData)
        let token = try fromData.seal(plaintext: "a@b.com", type: "EMAIL")
        let opened = try fromData.open(token: token)
        XCTAssertEqual(opened.plaintext, "a@b.com")
    }

    func testPlaintextAtExactLimitSucceeds() throws {
        let limited = SealEngine(key: key, maxPlaintextBytes: 256)
        let exact = String(repeating: "a", count: 256)
        let token = try limited.seal(plaintext: exact, type: "SECRET")
        let opened = try limited.open(token: token)
        XCTAssertEqual(opened.plaintext, exact)
    }

    func testUTF8ByteLimitNotCharacterCount() {
        let limited = SealEngine(key: key, maxPlaintextBytes: 10)
        // "я" is 2 UTF-8 bytes; 6 characters = 12 bytes > 10
        let cyrillic = String(repeating: "я", count: 6)
        XCTAssertEqual(Data(cyrillic.utf8).count, 12)
        XCTAssertThrowsError(try limited.seal(plaintext: cyrillic, type: "SECRET")) { error in
            XCTAssertEqual(
                error as? SealError,
                .plaintextTooLarge(byteCount: 12, limit: 10)
            )
        }
    }

    func testUnicodeRoundTrip() throws {
        let value = "привет 👋 ivan@пример.рф"
        let token = try engine.seal(plaintext: value, type: "EMAIL")
        let opened = try engine.open(token: token)
        XCTAssertEqual(opened.plaintext, value)
    }

    func testCiphertextTamperingFailsOpen() throws {
        let token = try engine.seal(plaintext: "ivan@acme.com", type: "EMAIL")
        let tampered = flipPayloadByte(in: token)
        XCTAssertNotEqual(tampered, token)
        XCTAssertThrowsError(try engine.open(token: tampered)) { error in
            let sealError = error as? SealError
            XCTAssertTrue(
                sealError == .decryptionFailed || sealError == .invalidTokenFormat,
                "Expected decryptionFailed or invalidTokenFormat, got \(String(describing: error))"
            )
        }
    }

    func testInvalidTokenFormats() {
        let cases = [
            "not-a-token",
            "{{EMAIL:v1.}}",
            "{{EMAIL:v1.!!!}}",
            "{{EMAIL:v1}}",
            "EMAIL:v1.abc",
            "{{:v1.abc}}",
        ]
        for token in cases {
            XCTAssertThrowsError(try engine.open(token: token), "Expected failure for \(token)") { error in
                guard let sealError = error as? SealError else {
                    return XCTFail("Expected SealError for \(token), got \(error)")
                }
                switch sealError {
                case .invalidTokenFormat, .unsupportedTokenVersion, .decryptionFailed:
                    break
                default:
                    XCTFail("Unexpected SealError for \(token): \(sealError)")
                }
            }
        }
    }

    func testUnsealFailsFastOnBadTokenAmongGood() throws {
        let good = try engine.seal(plaintext: "ivan@acme.com", type: "EMAIL")
        let text = "before \(good) {{EMAIL:v1.not-valid-payload}} after"
        XCTAssertThrowsError(try engine.unseal(text: text)) { error in
            let sealError = error as? SealError
            XCTAssertTrue(
                sealError == .decryptionFailed || sealError == .invalidTokenFormat,
                "Expected decryptionFailed or invalidTokenFormat, got \(String(describing: error))"
            )
        }
    }

    func testUnsealMultipleDistinctTokens() throws {
        let email = try engine.seal(plaintext: "a@b.com", type: "EMAIL")
        let phone = try engine.seal(plaintext: "+15551234567", type: "PHONE")
        let text = "mail \(email) call \(phone) done"
        let restored = try engine.unseal(text: text)
        XCTAssertEqual(restored, "mail a@b.com call +15551234567 done")
    }

    func testSealTextWithNoEntitiesLeavesTextUnchanged() throws {
        let text = "nothing sensitive"
        let result = try engine.seal(text: text, entities: [])
        XCTAssertEqual(result.sealedText, text)
        XCTAssertEqual(result.sealedCount, 0)
    }

    func testSealTextSkipsEntityWhenValueDoesNotMatchRange() throws {
        let text = "mail ivan@acme.com"
        guard let range = text.range(of: "ivan@acme.com") else {
            return XCTFail("missing email")
        }
        let mismatched = SensitiveEntity(
            type: .email,
            range: range,
            value: "other@acme.com",
            confidence: 1,
            source: .regex
        )
        let result = try engine.seal(text: text, entities: [mismatched])
        XCTAssertEqual(result.sealedText, text)
        XCTAssertEqual(result.sealedCount, 0)
    }

    func testSealTextSkipsOverlappingEntity() throws {
        let text = "ivan@acme.com"
        let full = entity(.email, "ivan@acme.com", in: text)
        guard let innerRange = text.range(of: "acme.com") else {
            return XCTFail("missing inner range")
        }
        let overlapping = SensitiveEntity(
            type: .internalDomain,
            range: innerRange,
            value: "acme.com",
            confidence: 1,
            source: .regex
        )
        let result = try engine.seal(text: text, entities: [full, overlapping])
        XCTAssertEqual(result.sealedCount, 1)
        XCTAssertFalse(result.sealedText.contains("ivan@acme.com"))
        XCTAssertEqual(try engine.unseal(text: result.sealedText), text)
    }

    func testFixedKeyProducesStableGoldenToken() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let a = try SealEngine(keyData: keyData)
        let b = try SealEngine(keyData: keyData)
        let tokenA = try a.seal(plaintext: "a@b.com", type: "EMAIL")
        let tokenB = try b.seal(plaintext: "a@b.com", type: "EMAIL")
        XCTAssertEqual(tokenA, tokenB)
        // Regression lock for nonce derivation + token framing (key bytes 0..<32).
        XCTAssertEqual(
            tokenA,
            "{{EMAIL:v1.ay0pF8pgS30I1UA9cZxHpe-EDanFkPg3ybpjGzk-L3jor00}}"
        )
    }

    private func flipPayloadByte(in token: String) -> String {
        guard token.hasPrefix("{{"),
              token.hasSuffix("}}"),
              let colon = token.firstIndex(of: ":"),
              token[token.index(after: colon)...].hasPrefix("v1.") else {
            return token + "x"
        }
        let payloadStart = token.index(colon, offsetBy: 4) // after ":v1."
        let payloadEnd = token.index(before: token.endIndex)
        guard payloadStart < payloadEnd else { return token + "x" }
        var chars = Array(token)
        let payloadIndices = token.distance(from: token.startIndex, to: payloadStart)
            ..< token.distance(from: token.startIndex, to: payloadEnd)
        guard let flipAt = payloadIndices.last else { return token + "x" }
        let current = chars[flipAt]
        chars[flipAt] = current == "A" ? "B" : "A"
        return String(chars)
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
