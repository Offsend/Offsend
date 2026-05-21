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
}
