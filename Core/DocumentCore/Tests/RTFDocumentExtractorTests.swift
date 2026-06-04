import AppKit
import XCTest
@testable import DocumentCore

final class RTFDocumentExtractorTests: XCTestCase {
    private let extractor = RTFDocumentExtractor()

    func testSupportsRTFExtensionOnly() {
        XCTAssertTrue(extractor.canExtract(source: DocumentSource(fileName: "memo.rtf")))
        XCTAssertFalse(extractor.canExtract(source: DocumentSource(fileName: "notes.txt")))
    }

    func testExtractsPlainTextWithoutControlWords() throws {
        let attributed = NSAttributedString(
            string: "Send invoice to ivan@acme.com",
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        )
        let data = try XCTUnwrap(
            attributed.rtf(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        )

        let result = try extractor.extract(
            DocumentTextExtractionRequest(
                data: data,
                source: DocumentSource(fileName: "memo.rtf"),
                maximumExtractedCharacterCount: 10_000
            )
        )

        XCTAssertEqual(result.format, .plainText)
        XCTAssertEqual(result.plainText, "Send invoice to ivan@acme.com")
        XCTAssertFalse(result.plainText.contains("\\rtf"))
    }

    func testRejectsInvalidRTFData() {
        let request = DocumentTextExtractionRequest(
            data: Data("not really rtf".utf8),
            source: DocumentSource(fileName: "broken.rtf"),
            maximumExtractedCharacterCount: 10_000
        )

        XCTAssertThrowsError(try extractor.extract(request)) { error in
            guard case .extractionFailed = error as? DocumentProcessingError else {
                return XCTFail("Expected extractionFailed, got \(error)")
            }
        }
    }
}
