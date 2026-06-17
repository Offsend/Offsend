import XCTest
@testable import DetectionCore

/// Corner cases that stress the windowed scanner, dedupe, UTF-16 handling, and the new validators.
/// Any failure here is a real bug, not just missing coverage.
final class DetectionEdgeCaseTests: XCTestCase {
    private let engine = DetectionEngine()

    // MARK: - Windowing

    /// A secret that straddles the first window boundary (at offset 40) must still be found via the
    /// overlapping window. The leading space gives the `\b`-anchored AWS rule a valid word boundary.
    func testSecretStraddlingWindowBoundaryIsDetected() async {
        let token = "AKIA1234567890ABCDEF" // 20 chars
        let text = String(repeating: "x", count: 29) + " " + token // token at [30,50), crosses boundary 40
        let result = await engine.scan(DetectionRequest(text: text, options: DetectionOptions(maximumLength: 40)))
        XCTAssertTrue(
            result.entities.contains { $0.type == .awsAccessKeyId && $0.value == token },
            "Straddling secret missed: \(result.entities.map { ($0.type, $0.value) })"
        )
    }

    /// The same secret matched in two overlapping windows must be reported once, not duplicated.
    func testSecretInOverlapRegionIsNotDuplicated() async {
        let token = "AKIA1234567890ABCDEF"
        let text = String(repeating: "y", count: 19) + " " + token + " zzz" // token at [20,40), total 44 > window
        let result = await engine.scan(DetectionRequest(text: text, options: DetectionOptions(maximumLength: 40)))
        let count = result.entities.filter { $0.type == .awsAccessKeyId }.count
        XCTAssertEqual(count, 1, "Overlap must dedupe a single occurrence, got \(count)")
    }

    /// Two identical secrets at different offsets are legitimate duplicates and must both be reported.
    func testIdenticalSecretsAtDifferentOffsetsBothDetected() async {
        let token = "AKIA1111111111111111"
        let text = token + "\n" + token // length 41 > window → windowed
        let result = await engine.scan(DetectionRequest(text: text, options: DetectionOptions(maximumLength: 40)))
        let count = result.entities.filter { $0.type == .awsAccessKeyId }.count
        XCTAssertEqual(count, 2, "Distinct occurrences must not be collapsed, got \(count)")
    }

    func testMultipleEmailsAcrossWindowsAllFound() async {
        let text = "u1@acme.com u2@acme.com u3@acme.com u4@acme.com"
        let result = await engine.scan(DetectionRequest(text: text, options: DetectionOptions(maximumLength: 20)))
        let emails = Set(result.entities.filter { $0.type == .email }.map(\.value))
        XCTAssertEqual(emails, ["u1@acme.com", "u2@acme.com", "u3@acme.com", "u4@acme.com"])
    }

    // MARK: - UTF-16 / multibyte

    /// Emoji before a secret shifts UTF-16 offsets; the matched value must still be exact.
    func testEmojiPrefixDoesNotCorruptSecretValue() async {
        let token = "AKIA1234567890ABCDEF"
        let text = String(repeating: "🔐", count: 30) + " " + token
        let result = await engine.scan(DetectionRequest(text: text, options: DetectionOptions(maximumLength: 40)))
        XCTAssertTrue(
            result.entities.contains { $0.type == .awsAccessKeyId && $0.value == token },
            "Emoji-shifted secret value corrupted: \(result.entities.map { ($0.type, $0.value) })"
        )
    }

    // MARK: - Validators

    func testCardWithDashSeparatorsDetected() async {
        let result = await engine.scan(DetectionRequest(text: "card 4111-1111-1111-1111 saved"))
        XCTAssertTrue(result.entities.contains { $0.type == .creditCardLike }, "Dashed valid card must be detected")
    }

    func testLowercaseIBANDetected() async {
        let result = await engine.scan(DetectionRequest(text: "iban gb82west12345698765432 ok"))
        XCTAssertTrue(result.entities.contains { $0.type == .iban }, "Lowercase IBAN must validate via mod-97")
    }

    // MARK: - Inline ignore

    func testInlineIgnoreHandlesCRLFLineEndings() async {
        let text = "aws = AKIA1234567890ABCDEF // offsend:ignore\r\nnext line"
        let result = await engine.scan(DetectionRequest(text: text, options: DetectionOptions(honorInlineIgnore: true)))
        XCTAssertFalse(result.entities.contains { $0.type == .awsAccessKeyId }, "CRLF line must still honor ignore")
    }
}
