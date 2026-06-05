import XCTest
@testable import DocumentCore

final class PDFDocumentExtractorTests: XCTestCase {
    private let extractor = PDFDocumentExtractor()

    func testSupportsPDFExtension() {
        XCTAssertTrue(extractor.canExtract(source: DocumentSource(fileName: "invoice.pdf")))
        XCTAssertFalse(extractor.canExtract(source: DocumentSource(fileName: "notes.txt")))
    }

    func testExtractsTextFromPDF() throws {
        let expectedText = "Hello from PDF"
        let data = PDFTestFixtures.makePDF(containing: expectedText)
        let result = try extractor.extract(
            DocumentTextExtractionRequest(
                data: data,
                source: DocumentSource(fileName: "hello.pdf"),
                maximumExtractedCharacterCount: 10_000
            )
        )

        XCTAssertEqual(result.format, DocumentFormat.pdf)
        XCTAssertTrue(result.plainText.contains(expectedText))
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testRejectsInvalidPDFData() {
        let request = DocumentTextExtractionRequest(
            data: Data("not-a-pdf".utf8),
            source: DocumentSource(fileName: "broken.pdf"),
            maximumExtractedCharacterCount: 10_000
        )

        XCTAssertThrowsError(try extractor.extract(request)) { error in
            XCTAssertEqual(error as? DocumentProcessingError, .invalidPDF)
        }
    }

    func testReturnsEmptyTextForPDFWithoutExtractableText() throws {
        let request = DocumentTextExtractionRequest(
            data: PDFTestFixtures.makeEmptyPDF(),
            source: DocumentSource(fileName: "blank.pdf"),
            maximumExtractedCharacterCount: 10_000
        )

        let result = try extractor.extract(request)
        XCTAssertEqual(result.format, DocumentFormat.pdf)
        XCTAssertTrue(result.plainText.isEmpty)
    }

    func testExtractsMultiplePagesSeparatedByBlankLine() throws {
        let data = PDFTestFixtures.makePDF(pages: ["Page one", "Page two"])
        let result = try extractor.extract(
            DocumentTextExtractionRequest(
                data: data,
                source: DocumentSource(fileName: "multi.pdf"),
                maximumExtractedCharacterCount: 10_000
            )
        )

        XCTAssertEqual(result.plainText, "Page one\n\nPage two")
    }

    func testSkipsBlankPagesAndExtractsRemainingText() throws {
        let data = PDFTestFixtures.makePDF(pages: ["", "Actual content"])
        let result = try extractor.extract(
            DocumentTextExtractionRequest(
                data: data,
                source: DocumentSource(fileName: "partial.pdf"),
                maximumExtractedCharacterCount: 10_000
            )
        )

        XCTAssertEqual(result.plainText, "Actual content")
    }

    func testMatchesUppercaseFileExtension() throws {
        let data = PDFTestFixtures.makePDF(containing: "Uppercase extension")
        let result = try extractor.extract(
            DocumentTextExtractionRequest(
                data: data,
                source: DocumentSource(fileName: "INVOICE.PDF"),
                maximumExtractedCharacterCount: 10_000
            )
        )

        XCTAssertTrue(result.plainText.contains("Uppercase extension"))
    }
}
