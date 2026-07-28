import DetectionCore
import XCTest
@testable import OffsendRuntime

final class OpaqueEncodedBlobScanTests: XCTestCase {
    func testExtractorDecodesBase64UTF8Payload() {
        let plaintext = "OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyzABCDEF123456"
        let encoded = Data(plaintext.utf8).base64EncodedString()
        XCTAssertGreaterThanOrEqual(encoded.count, OpaqueEncodedBlobExtractor.minBase64Length)

        let text = "terminal output:\n\(encoded)\n"
        let blobs = OpaqueEncodedBlobExtractor.candidates(in: text)
        XCTAssertEqual(blobs.count, 1)
        XCTAssertEqual(blobs[0].decodedUTF8, plaintext)
    }

    func testExtractorIgnoresShortBase64() {
        let short = Data("hi".utf8).base64EncodedString()
        XCTAssertTrue(OpaqueEncodedBlobExtractor.candidates(in: short).isEmpty)
    }

    func testRunTextFlagsBase64EncodedOpenAIKey() async {
        // Synthetic demo key shape — not a live credential.
        let plaintext = "OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyzABCDEF123456"
        let encoded = Data(plaintext.utf8).base64EncodedString()
        let terminalDump = """
        $ python3 -c 'print(base64…)'
        \(encoded)
        """

        let context = OffsendRuntimeContext(settings: .default, customDictionaries: [])
        let service = OffsendCheckService(context: context)
        let result = await service.runText(terminalDump, failPolicy: .block)
        XCTAssertTrue(
            result.entities.contains { $0.type.countsAsCriticalSecret },
            "expected critical secret from decoded base64, got \(result.entities.map(\.type))"
        )
        // The flagged span should be the encoded blob, not only plaintext (there is none).
        XCTAssertTrue(
            result.entities.contains { entity in
                String(result.scannedText[entity.range]).contains(String(encoded.prefix(16)))
            }
        )
    }

    func testRunTextIgnoresBenignLongBase64WithoutSecrets() async {
        let benign = Data(String(repeating: "lorem ipsum ", count: 20).utf8).base64EncodedString()
        let context = OffsendRuntimeContext(settings: .default, customDictionaries: [])
        let service = OffsendCheckService(context: context)
        let result = await service.runText("blob=\(benign)", failPolicy: .block)
        XCTAssertFalse(result.entities.contains { $0.type.countsAsCriticalSecret })
    }

    func testRunTextFlagsWrappedBase64Secret() async {
        let plaintext = "OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyzABCDEF123456"
        let encoded = Data(plaintext.utf8).base64EncodedString()
        let split = encoded.index(encoded.startIndex, offsetBy: 32)
        let wrapped = "\(encoded[..<split])\n\(encoded[split...])"
        let context = OffsendRuntimeContext(settings: .default, customDictionaries: [])
        let result = await OffsendCheckService(context: context).runText(wrapped)

        XCTAssertTrue(result.entities.contains { $0.type == .openAIAPIKey })
        XCTAssertFalse(result.opaqueScanOverflow)
    }

    func testRunTextMarksOpaqueBudgetOverflow() async {
        let payloads = (0...OpaqueEncodedBlobExtractor.maxBlobsPerText).map { index in
            Data("value-\(index)-abcdefghijklmnop".utf8).base64EncodedString()
        }
        let context = OffsendRuntimeContext(settings: .default, customDictionaries: [])
        let result = await OffsendCheckService(context: context).runText(
            payloads.joined(separator: ":")
        )

        XCTAssertTrue(result.opaqueScanOverflow)
    }
}
