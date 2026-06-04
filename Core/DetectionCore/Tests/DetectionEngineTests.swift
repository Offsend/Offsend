import XCTest
@testable import DetectionCore

final class DetectionEngineTests: XCTestCase {
    private let engine = DetectionEngine()

    func testDetectsEmailPhoneMoneyURLAndContract() {
        let text = "Contact ivan@acme.com at +1 415 555 1212 for CN-4812 worth $80,000. See https://example.com and portal.acme.internal"
        let result = engine.scan(DetectionRequest(text: text))
        let types = Set(result.entities.map(\.type))

        XCTAssertTrue(types.contains(.email))
        XCTAssertTrue(types.contains(.phone))
        XCTAssertTrue(types.contains(.money))
        XCTAssertTrue(types.contains(.contractId))
        XCTAssertTrue(types.contains(.url))
        XCTAssertTrue(types.contains(.internalDomain))
    }

    func testDetectsSecretPatterns() {
        let text = "OPENAI sk-abcdefghijklmnopqrstuvwxyzABCDEF123456 and jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature"
        let result = engine.scan(DetectionRequest(text: text))
        let types = Set(result.entities.map(\.type))

        XCTAssertTrue(types.contains(.openAIAPIKey))
        XCTAssertTrue(types.contains(.jwt))
    }

    func testSwiftClosureDollarDigitsNotDetectedAsMoney() {
        let text =
            #"let cursedColor = (([0xDEADBEEF].enumerated().reduce(CGFloat(0)) { $0 + CGFloat(($1.element >> ($1.offset * 8)) & 0xFF) / 255.0 })"#
        let result = engine.scan(DetectionRequest(text: text))
        XCTAssertFalse(
            result.entities.contains { $0.type == .money },
            "Expected no money from Swift `$0` / `$1`, got: \(result.entities.map(\.type))"
        )
    }

    func testDetectsMultiDigitDollarAmounts() {
        let text = "Pay $50 today and $1,200 tomorrow"
        let result = engine.scan(DetectionRequest(text: text))
        let money = result.entities.filter { $0.type == .money }.map(\.value).sorted()
        XCTAssertEqual(money, ["$1,200", "$50"])
    }

    func testCustomDictionaryMatchesClientName() {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .client, value: "Acme Corp")
        ])

        let result = engine.scan(DetectionRequest(text: "Send Acme Corp proposal", options: options))

        XCTAssertEqual(result.entities.first?.type, .customClient)
        XCTAssertEqual(result.entities.first?.value, "Acme Corp")
    }

    func testTruncatesLongClipboardText() {
        let result = engine.scan(DetectionRequest(text: String(repeating: "a", count: 20), options: DetectionOptions(maximumLength: 10)))

        XCTAssertTrue(result.wasTruncated)
        XCTAssertEqual(result.scannedCharacterCount, 10)
    }

    func testSpacedCardNumberNotDetectedAsPhone() {
        let text = "4242 4242 4242 4242"
        let result = engine.scan(DetectionRequest(text: text))
        XCTAssertTrue(result.entities.contains { $0.type == .creditCardLike }, "Expected card-like entity, got: \(result.entities.map(\.type))")
        XCTAssertFalse(result.entities.contains { $0.type == .phone }, "PAN-shaped value must not be a phone: \(result.entities.map(\.type))")
        XCTAssertEqual(result.entities.first { $0.type == .creditCardLike }?.value, text)
    }

    func testIPv4ListNotDetectedAsPhones() {
        let text = """
        160.79.104.10
        34.36.57.103
        104.16.174.226
        104.16.175.22
        """
        let result = engine.scan(DetectionRequest(text: text))
        XCTAssertFalse(result.entities.contains { $0.type == .phone }, "IPv4 quads must not be phones: \(result.entities.map(\.type))")
        let ips = result.entities.filter { $0.type == .ipAddress }.map(\.value).sorted()
        XCTAssertEqual(ips, ["104.16.174.226", "104.16.175.22", "160.79.104.10", "34.36.57.103"])
    }

    func testPhotoFilenameDateAndTimeNotDetectedAsPhone() {
        let dashed = "photo_2026-04-23 16.50.15.jpeg"
        let dotted = "photo_2026.04.23 16.50.15.jpeg"
        let maskedPlaceholder = "photo_{{PHONE_1}} 16.50.15.jpeg"

        for text in [dashed, dotted, maskedPlaceholder] {
            let result = engine.scan(DetectionRequest(text: text))
            XCTAssertFalse(
                result.entities.contains { $0.type == .phone },
                "Expected no phone in: \(text), got: \(result.entities.map(\.type))"
            )
        }
    }

    func testCustomDictionaryWinsOverlap() {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .internalDomain, value: "portal.acme.internal")
        ])

        let result = engine.scan(DetectionRequest(text: "https://portal.acme.internal/login", options: options))

        XCTAssertTrue(result.entities.contains { $0.type == .customInternalDomain })
    }

    func testSparkleEdSignaturesDetectedAsHighEntropySecrets() {
        let sig1 = "pNFd7KbcQSu+Mq7UYrbQXTPq82luht2ACXm/r2utp1u/Uv/5hWqctdT2jwQgMejW7DRoeV/hVr6J4VdZYdwWDw=="
        let sig2 = "Ody3D/ybSMH4T+P/oNj3LN4F0SA8RJGLEr1TI4UemrBAiJ9aEcDnYV3u58P75AbcFjI13jPYmHDUHXMSTFQbDw=="
        let text = """
        <enclosure sparkle:edSignature="\(sig1)" />
        <enclosure sparkle:edSignature="\(sig2)" />
        """
        let result = engine.scan(DetectionRequest(text: text))
        let secrets = result.entities.filter { $0.type == .highEntropyString }.map(\.value)

        XCTAssertEqual(secrets, [sig1, sig2])
    }

    func testFigmaFileURLDoesNotFalsePositiveAsSecretOrPhone() {
        // Synthetic Figma-shaped URL (no real file key or client project name).
        let text =
            "https://www.figma.com/design/AbCdEfGhIjKlMnOqRsTuVwXyZ/Example-Design-File?node-id=12-345&t=ZzYyXxWwVvUuTtSs-1"
        let result = engine.scan(DetectionRequest(text: text))
        let types = Set(result.entities.map(\.type))

        XCTAssertTrue(types.contains(.url), "Expected URL entity, got: \(types)")
        XCTAssertFalse(types.contains(.highEntropyString), "Path must not match fuzzy high-entropy rule: \(types)")
        XCTAssertFalse(types.contains(.phone), "`node-id=12-345` must not be a phone: \(types)")
    }

    // MARK: - OverlapResolver coverage (no leaks)

    func testOverlapMergePreservesFullCoverageWhenHigherPriorityIsShorter() {
        let text = "0123456789"
        func range(_ lower: Int, _ upper: Int) -> Range<String.Index> {
            let lo = text.index(text.startIndex, offsetBy: lower)
            let hi = text.index(text.startIndex, offsetBy: upper)
            return lo..<hi
        }
        // Long fuzzy match fully containing a short, higher-priority secret.
        let high = SensitiveEntity(
            type: .highEntropyString, range: range(0, 10), value: String(text[range(0, 10)]),
            confidence: 0.65, source: .secret
        )
        let aws = SensitiveEntity(
            type: .awsAccessKeyId, range: range(2, 6), value: String(text[range(2, 6)]),
            confidence: 0.99, source: .secret
        )

        let merged = OverlapResolver.resolve([high, aws], in: text)

        XCTAssertEqual(merged.count, 1, "Overlapping spans must collapse to one entity")
        XCTAssertEqual(merged.first?.type, .awsAccessKeyId, "Higher-priority metadata wins")
        XCTAssertEqual(
            merged.first.map { String(text[$0.range]) }, text,
            "Merged range must cover the union so no flagged character is left unmasked"
        )
    }

    // MARK: - Truncation

    func testTruncationCutsOnTokenBoundary() {
        let result = engine.scan(
            DetectionRequest(text: "alpha bravo charlie", options: DetectionOptions(maximumLength: 15))
        )

        XCTAssertTrue(result.wasTruncated)
        XCTAssertEqual(result.scannedText, "alpha bravo", "Trailing partial token must be dropped")
        XCTAssertEqual(result.scannedCharacterCount, 11)
    }

    func testTruncationFallsBackToHardCutWithoutWhitespace() {
        let result = engine.scan(
            DetectionRequest(text: String(repeating: "a", count: 20), options: DetectionOptions(maximumLength: 10))
        )

        XCTAssertTrue(result.wasTruncated)
        XCTAssertEqual(result.scannedCharacterCount, 10)
    }

    // MARK: - Phone boundary

    func testPhoneEmbeddedInAlphanumericTokenNotDetected() {
        let result = engine.scan(DetectionRequest(text: "build abc1234567890 done"))
        XCTAssertFalse(
            result.entities.contains { $0.type == .phone },
            "Digits embedded in an alphanumeric token must not start a phone match: \(result.entities.map(\.type))"
        )
    }

    func testPhoneSeparatorDoesNotBridgeAcrossNewline() {
        let text = "555 1212\n333 4444"
        let result = engine.scan(DetectionRequest(text: text))
        for entity in result.entities where entity.type == .phone {
            XCTAssertFalse(entity.value.contains("\n"), "A phone match must not span a newline: \(entity.value)")
        }
    }

    func testMoneySeparatorDoesNotBridgeAcrossNewline() {
        let text = "$80,000\n160 reasons"
        let result = engine.scan(DetectionRequest(text: text))
        let money = result.entities.filter { $0.type == .money }.map(\.value)
        XCTAssertEqual(money, ["$80,000"], "Money must stop at the line break, not absorb the next line")
    }

    // MARK: - Custom internal domain boundaries

    func testCustomInternalDomainDoesNotMatchSubstringOfLargerHost() {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .internalDomain, value: "acme.internal")
        ])

        let result = engine.scan(DetectionRequest(text: "host notacme.internalx pinged", options: options))

        XCTAssertFalse(result.entities.contains { $0.type == .customInternalDomain })
    }

    func testCustomInternalDomainMatchesStandaloneHost() {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .internalDomain, value: "acme.internal")
        ])

        let result = engine.scan(DetectionRequest(text: "open https://acme.internal/x", options: options))

        XCTAssertTrue(result.entities.contains { $0.type == .customInternalDomain })
    }
}
