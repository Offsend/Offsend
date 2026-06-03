import XCTest
@testable import DocumentCore

final class PlainTextDocumentExtractorTests: XCTestCase {
    private let extractor = PlainTextDocumentExtractor()

    func testSupportsPlainTextExtensions() {
        XCTAssertTrue(extractor.canExtract(source: DocumentSource(fileName: "notes.txt")))
        XCTAssertTrue(extractor.canExtract(source: DocumentSource(fileName: "README.md")))
        XCTAssertTrue(extractor.canExtract(source: DocumentSource(fileName: "data.csv")))
        XCTAssertFalse(extractor.canExtract(source: DocumentSource(fileName: "scan.pdf")))
    }

    func testExtractsUTF8Text() throws {
        let data = Data("Hello, world".utf8)
        let result = try extractor.extract(
            DocumentTextExtractionRequest(
                data: data,
                source: DocumentSource(fileName: "hello.txt"),
                maximumExtractedCharacterCount: 10_000
            )
        )

        XCTAssertEqual(result.format, .plainText)
        XCTAssertEqual(result.plainText, "Hello, world")
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testFallsBackToLatin1Encoding() throws {
        let bytes: [UInt8] = [0xC0, 0xE9, 0xF9] // "Àéù" in Latin-1
        let data = Data(bytes)
        let result = try extractor.extract(
            DocumentTextExtractionRequest(
                data: data,
                source: DocumentSource(fileName: "latin1.txt"),
                maximumExtractedCharacterCount: 10_000
            )
        )

        XCTAssertEqual(result.plainText, "Àéù")
    }

    func testMatchesUppercaseFileExtension() {
        XCTAssertTrue(extractor.canExtract(source: DocumentSource(fileName: "NOTES.TXT")))
    }
}
