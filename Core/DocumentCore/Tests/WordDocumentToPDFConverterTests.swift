import AppKit
import PDFKit
import XCTest
@testable import DocumentCore

final class WordDocumentToPDFConverterTests: XCTestCase {
    func testConvertsDocxToSearchablePDF() throws {
        let docxData = try WordTestFixtures.makeDocx(containing: "Send invoice to ivan@acme.com")
        let converter = AppKitWordDocumentToPDFConverter()

        let pdfData = try converter.convert(data: docxData, fileExtension: "docx")

        guard let document = PDFDocument(data: pdfData) else {
            XCTFail("Expected valid PDF output")
            return
        }

        XCTAssertGreaterThan(document.pageCount, 0)
        XCTAssertTrue(document.string?.contains("ivan@acme.com") == true)
    }

    func testConvertsDocToSearchablePDF() throws {
        let docData = try WordTestFixtures.makeDoc(containing: "Send invoice to ivan@acme.com")
        let converter = AppKitWordDocumentToPDFConverter()

        let pdfData = try converter.convert(data: docData, fileExtension: "doc")

        guard let document = PDFDocument(data: pdfData) else {
            XCTFail("Expected valid PDF output")
            return
        }

        XCTAssertGreaterThan(document.pageCount, 0)
        XCTAssertTrue(document.string?.contains("ivan@acme.com") == true)
    }

    func testRejectsUnsupportedExtension() {
        let converter = AppKitWordDocumentToPDFConverter()

        XCTAssertThrowsError(try converter.convert(data: Data(), fileExtension: "rtf")) { error in
            XCTAssertEqual(error as? DocumentProcessingError, .unsupportedFormat(fileExtension: "rtf"))
        }
    }

}
