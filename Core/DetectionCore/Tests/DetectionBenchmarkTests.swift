import XCTest
@testable import DetectionCore

/// A small labeled corpus that locks detection behavior: every positive must be caught (recall) and no
/// negative may flag (precision). Add real-world samples here when fixing a miss or a false positive so
/// regressions are caught before release. Keep negatives currently-clean — a failure means a real FP.
final class DetectionBenchmarkTests: XCTestCase {
    private let engine = DetectionEngine()

    /// Inputs that MUST produce at least one finding.
    private let positives: [String] = [
        "Contact us at ivan@acme.com about the renewal",
        "call +1 415 555 1212 tomorrow",
        "OPENAI=sk-abcdefghijklmnopqrstuvwxyzABCDEF123456",
        "aws id AKIA1234567890ABCDEF rotated",
        "token ghp_0123456789abcdefABCDEF0123456789ab",
        "STRIPE=sk_live_0123456789abcdefABCDEF12",
        "groq gsk_012345678901234567890123456789",
        "auth eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature",
        "card 4111 1111 1111 1111 on file",
        "iban GB82WEST12345698765432 for payout",
        """
        -----BEGIN PRIVATE KEY-----
        MIIBVwIBADANBgkqhkiG9w0BAQEFAASCAUEwggE9AgEAAkEA
        -----END PRIVATE KEY-----
        """,
    ]

    /// Inputs that MUST stay clean (common false-positive shapes).
    private let negatives: [String] = [
        "color #FF5733 used for the header background",
        "see src/components/Button/index.tsx for details",
        "OffsendStrings.settingsLicensePricingFallbackSubheadline",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "lorem ipsum dolor sit amet consectetur adipiscing",
        "function getUserById(userId: string): User",
        "upgrade to version 1.2.3 of the parser",
        "the placeholder key is sk-your-api-key-here-xxxxxxxxxxxxxxxx",
        "an invalid card 1234 5678 9012 3456 in the sample",
    ]

    func testCorpusPrecisionAndRecall() async {
        var detectedPositives = 0
        for sample in positives {
            let result = await engine.scan(DetectionRequest(text: sample))
            if result.entities.isEmpty {
                XCTFail("False negative (missed): \(sample)")
            } else {
                detectedPositives += 1
            }
        }

        var falsePositives = 0
        for sample in negatives {
            let result = await engine.scan(DetectionRequest(text: sample))
            if !result.entities.isEmpty {
                falsePositives += 1
                XCTFail("False positive: \(sample) -> \(result.entities.map { ($0.type, $0.value) })")
            }
        }

        let recall = Double(detectedPositives) / Double(positives.count)
        let precision = Double(detectedPositives) / Double(detectedPositives + falsePositives)
        print(String(format: "Detection corpus — recall: %.2f, precision: %.2f", recall, precision))

        XCTAssertEqual(recall, 1.0, "Every positive sample must be detected")
        XCTAssertEqual(falsePositives, 0, "No negative sample may flag")
    }
}
