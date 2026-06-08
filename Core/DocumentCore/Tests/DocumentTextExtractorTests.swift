import XCTest
@testable import DocumentCore

final class DocumentTextExtractorTests: XCTestCase {
    private let extractor = DocumentTextExtractor()

    func testRejectsEmptyDocumentAfterTrimming() {
        let request = DocumentProcessingRequest(
            data: Data("   \n\t  ".utf8),
            source: DocumentSource(fileName: "empty.txt")
        )

        XCTAssertThrowsError(try extractor.extract(request)) { error in
            XCTAssertEqual(error as? DocumentProcessingError, .emptyDocument)
        }
    }

    func testTruncatesLongExtractedText() throws {
        let text = String(repeating: "a", count: 50)
        let request = DocumentProcessingRequest(
            data: Data(text.utf8),
            source: DocumentSource(fileName: "long.txt"),
            options: DocumentProcessingOptions(maximumExtractedCharacterCount: 20)
        )

        let extracted = try extractor.extract(request)

        XCTAssertEqual(extracted.plainText.count, 20)
        XCTAssertTrue(extracted.wasTruncated)
        XCTAssertTrue(extracted.warnings.contains {
            $0 == .textTruncated(originalCharacterCount: 50, maximumCharacterCount: 20)
        })
    }

    func testExtractsDocxThroughDefaultRegistry() throws {
        let docxData = try WordTestFixtures.makeDocx(containing: "Contact ivan@acme.com")
        let request = DocumentProcessingRequest(
            data: docxData,
            source: DocumentSource(fileName: "notes.docx")
        )

        let extracted = try extractor.extract(request)

        XCTAssertEqual(extracted.extractorID, "word")
        XCTAssertEqual(extracted.format, .pdf)
        XCTAssertNotNil(extracted.pdfData)
        XCTAssertTrue(extracted.plainText.contains("ivan@acme.com"))
    }

    func testRejectsOversizedFile() {
        let request = DocumentProcessingRequest(
            data: Data(repeating: 0x41, count: 20),
            source: DocumentSource(fileName: "large.txt"),
            options: DocumentProcessingOptions(maximumFileByteCount: 10)
        )

        XCTAssertThrowsError(try extractor.extract(request)) { error in
            XCTAssertEqual(error as? DocumentProcessingError, .fileTooLarge(byteCount: 20, maximumByteCount: 10))
        }
    }

    func testExtractsPDFThroughDefaultRegistry() throws {
        let pdfData = PDFTestFixtures.makePDF(containing: "PDF via registry")
        let request = DocumentProcessingRequest(
            data: pdfData,
            source: DocumentSource(fileName: "invoice.pdf")
        )

        let extracted = try extractor.extract(request)

        XCTAssertEqual(extracted.extractorID, "pdf")
        XCTAssertEqual(extracted.format, DocumentFormat.pdf)
        XCTAssertTrue(extracted.plainText.contains("PDF via registry"))
    }

    func testRejectsInvalidPDFThroughDefaultRegistry() {
        let request = DocumentProcessingRequest(
            data: Data("not-a-pdf".utf8),
            source: DocumentSource(fileName: "broken.pdf")
        )

        XCTAssertThrowsError(try extractor.extract(request)) { error in
            XCTAssertEqual(
                error as? DocumentProcessingError,
                .invalidPDF
            )
        }
    }

    func testExtractsEmptyPDFThroughDefaultRegistry() throws {
        let request = DocumentProcessingRequest(
            data: PDFTestFixtures.makeEmptyPDF(),
            source: DocumentSource(fileName: "blank.pdf")
        )

        let extracted = try extractor.extract(request)

        XCTAssertEqual(extracted.format, DocumentFormat.pdf)
        XCTAssertTrue(extracted.plainText.isEmpty)
    }

    func testTruncatesLongExtractedPDFText() throws {
        let text = String(repeating: "a", count: 50)
        let request = DocumentProcessingRequest(
            data: PDFTestFixtures.makePDF(containing: text),
            source: DocumentSource(fileName: "long.pdf"),
            options: DocumentProcessingOptions(maximumExtractedCharacterCount: 20)
        )

        let extracted = try extractor.extract(request)

        XCTAssertEqual(extracted.plainText.count, 20)
        XCTAssertTrue(extracted.wasTruncated)
    }

}
