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

    func testSupportsUnknownTextExtensionWithoutURL() {
        XCTAssertTrue(extractor.canExtract(source: DocumentSource(fileName: "notes.tt")))
    }

    func testSupportsUnknownTextExtensionWithTextContent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample-\(UUID().uuidString).tt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "Hello from a custom extension".write(to: url, atomically: true, encoding: .utf8)

        let source = DocumentSource(fileName: url.lastPathComponent, sourceURL: url)
        XCTAssertTrue(extractor.canExtract(source: source))
    }

    func testRejectsBinaryFileWithUnknownExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("binary-\(UUID().uuidString).tt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0x00, 0x01, 0x02, 0xFF]).write(to: url)

        let source = DocumentSource(fileName: url.lastPathComponent, sourceURL: url)
        XCTAssertFalse(extractor.canExtract(source: source))
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
