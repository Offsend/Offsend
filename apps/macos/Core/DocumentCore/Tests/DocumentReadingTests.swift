import XCTest
@testable import DocumentCore

final class DocumentReadingTests: XCTestCase {
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample-invoice.txt")
    }

    func testReadsExistingFile() throws {
        let reader = FileManagerDocumentReader()
        let data = try reader.data(at: fixtureURL)

        XCTAssertFalse(data.isEmpty)
    }

    func testRejectsMissingFile() {
        let reader = FileManagerDocumentReader()
        let missingURL = fixtureURL.deletingLastPathComponent().appendingPathComponent("missing.txt")

        XCTAssertThrowsError(try reader.data(at: missingURL)) { error in
            XCTAssertEqual(
                error as? DocumentProcessingError,
                .unreadableFile(message: "File does not exist.")
            )
        }
    }

    func testDocumentProcessingRequestLoadsFileURL() throws {
        let request = try DocumentProcessingRequest(fileURL: fixtureURL)

        XCTAssertEqual(request.source.fileName, "sample-invoice.txt")
        XCTAssertEqual(request.source.fileExtension, "txt")
        XCTAssertFalse(request.data.isEmpty)
    }

    func testDocumentProcessingRequestRejectsMissingFileURL() {
        let missingURL = fixtureURL.deletingLastPathComponent().appendingPathComponent("missing.txt")

        XCTAssertThrowsError(try DocumentProcessingRequest(fileURL: missingURL)) { error in
            XCTAssertEqual(
                error as? DocumentProcessingError,
                .unreadableFile(message: "File does not exist.")
            )
        }
    }

    func testDocumentProcessingRequestRejectsOversizedFileURL() throws {
        XCTAssertThrowsError(
            try DocumentProcessingRequest(
                fileURL: fixtureURL,
                options: DocumentProcessingOptions(maximumFileByteCount: 10)
            )
        ) { error in
            guard case let .fileTooLarge(byteCount, maximumByteCount) = error as? DocumentProcessingError else {
                return XCTFail("Expected fileTooLarge, got \(error)")
            }
            XCTAssertGreaterThan(byteCount, maximumByteCount)
            XCTAssertEqual(maximumByteCount, 10)
        }
    }
}

final class DocumentSourceTests: XCTestCase {
    func testNormalizesFileExtensionToLowercase() {
        let source = DocumentSource(fileName: "Invoice.PDF")

        XCTAssertEqual(source.fileExtension, "pdf")
    }

    func testReturnsEmptyExtensionForExtensionlessFileName() {
        let source = DocumentSource(fileName: "README")

        XCTAssertEqual(source.fileExtension, "")
    }
}
