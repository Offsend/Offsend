import XCTest
@testable import DetectionCore

final class OpaqueEncodedBlobExtractorTests: XCTestCase {
    func testDecodesHexUTF8Payload() {
        let plaintext = "postgres://demo:SuperSecretPass123@db.example.com:5432/app"
        let hex = plaintext.utf8.map { String(format: "%02x", $0) }.joined()
        XCTAssertGreaterThanOrEqual(hex.count, OpaqueEncodedBlobExtractor.minHexLength)

        let blobs = OpaqueEncodedBlobExtractor.candidates(in: "out \(hex) end")
        XCTAssertEqual(blobs.count, 1)
        XCTAssertEqual(blobs[0].decodedUTF8, plaintext)
    }

    func testSkipsNonUTF8BinaryBase64() {
        let binary = Data((0..<64).map { UInt8($0) }).base64EncodedString()
        XCTAssertTrue(OpaqueEncodedBlobExtractor.candidates(in: binary).isEmpty)
    }

    func testRejoinsWrappedBase64() {
        let plaintext = "OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyzABCDEF123456"
        let encoded = Data(plaintext.utf8).base64EncodedString()
        let chunks = stride(from: 0, to: encoded.count, by: 20).map { offset -> String in
            let start = encoded.index(encoded.startIndex, offsetBy: offset)
            let end = encoded.index(start, offsetBy: min(20, encoded.distance(from: start, to: encoded.endIndex)))
            return String(encoded[start..<end])
        }
        let extraction = OpaqueEncodedBlobExtractor.extract(in: chunks.joined(separator: "\n"))
        XCTAssertFalse(extraction.exceededSafetyBudget)
        XCTAssertEqual(extraction.blobs.map(\.decodedUTF8), [plaintext])
    }

    func testReportsOverflowInsteadOfDroppingTailCandidates() {
        let payloads = (0...OpaqueEncodedBlobExtractor.maxBlobsPerText).map { index in
            Data("value-\(index)-abcdefghijklmnop".utf8).base64EncodedString()
        }
        let extraction = OpaqueEncodedBlobExtractor.extract(in: payloads.joined(separator: ":"))
        XCTAssertTrue(extraction.exceededSafetyBudget)
        XCTAssertEqual(extraction.blobs.count, OpaqueEncodedBlobExtractor.maxBlobsPerText)
    }
}
