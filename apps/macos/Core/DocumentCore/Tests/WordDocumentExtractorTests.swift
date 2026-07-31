import AppKit
import PDFKit
import XCTest
@testable import DocumentCore

final class WordDocumentExtractorTests: XCTestCase {
    func testSupportsDocAndDocxExtensions() {
        let extractor = WordDocumentExtractor()

        XCTAssertTrue(extractor.canExtract(source: DocumentSource(fileName: "memo.docx")))
        XCTAssertTrue(extractor.canExtract(source: DocumentSource(fileName: "legacy.doc")))
        XCTAssertFalse(extractor.canExtract(source: DocumentSource(fileName: "notes.pdf")))
    }

    func testExtractsDocxAsPDFWithConvertedData() throws {
        let docxData = try WordTestFixtures.makeDocx(containing: "Contact ivan@acme.com for invoice CN-4812")
        let extractor = WordDocumentExtractor()

        let result = try extractor.extract(
            DocumentTextExtractionRequest(
                data: docxData,
                source: DocumentSource(fileName: "invoice.docx"),
                maximumExtractedCharacterCount: 500_000
            )
        )

        XCTAssertEqual(result.format, .pdf)
        XCTAssertTrue(result.plainText.contains("ivan@acme.com"))
        XCTAssertNotNil(result.pdfData)
        XCTAssertNotNil(PDFDocument(data: result.pdfData!))
    }

    func testUsesInjectedConverter() throws {
        let expectedPDF = PDFTestFixtures.makePDF(containing: "stubbed pdf text")
        let extractor = WordDocumentExtractor(converter: StubWordDocumentToPDFConverter(pdfData: expectedPDF))

        let result = try extractor.extract(
            DocumentTextExtractionRequest(
                data: Data("ignored".utf8),
                source: DocumentSource(fileName: "memo.doc"),
                maximumExtractedCharacterCount: 500_000
            )
        )

        XCTAssertEqual(result.format, .pdf)
        XCTAssertEqual(result.pdfData, expectedPDF)
        XCTAssertTrue(result.plainText.contains("stubbed pdf text"))
    }

    func testExtractsDocAsPDFWithConvertedData() throws {
        let docData = try WordTestFixtures.makeDoc(containing: "Send invoice to ivan@acme.com")
        let extractor = WordDocumentExtractor()

        let result = try extractor.extract(
            DocumentTextExtractionRequest(
                data: docData,
                source: DocumentSource(fileName: "legacy.doc"),
                maximumExtractedCharacterCount: 500_000
            )
        )

        XCTAssertEqual(result.format, .pdf)
        XCTAssertTrue(result.plainText.contains("ivan@acme.com"))
        XCTAssertNotNil(result.pdfData)
    }

    func testRejectsUnreadableWordDocument() {
        let extractor = WordDocumentExtractor()

        XCTAssertThrowsError(
            try extractor.extract(
                DocumentTextExtractionRequest(
                    data: Data("not-a-word-file".utf8),
                    source: DocumentSource(fileName: "broken.docx"),
                    maximumExtractedCharacterCount: 500_000
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? DocumentProcessingError,
                .extractionFailed(message: "Unable to read Word document.")
            )
        }
    }

}

private struct StubWordDocumentToPDFConverter: WordDocumentToPDFConverting {
    let pdfData: Data

    func convert(data: Data, fileExtension: String) throws -> Data {
        pdfData
    }
}
