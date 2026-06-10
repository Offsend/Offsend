import XCTest
@testable import DocumentCore

final class DocumentTextExtractorRegistryTests: XCTestCase {
    func testSelectsFirstMatchingExtractor() {
        let registry = DocumentTextExtractorRegistry(extractors: [
            StubDocumentTextExtractor(id: "pdf", extensions: ["pdf"]),
            StubDocumentTextExtractor(id: "plain-text", extensions: ["txt", "md"])
        ])

        let selected = registry.extractor(for: DocumentSource(fileName: "notes.txt"))
        XCTAssertEqual(selected?.id, "plain-text")
    }

    func testDefaultRegistrySupportsPDF() {
        let registry = DocumentTextExtractorRegistry.default

        XCTAssertEqual(registry.extractor(for: DocumentSource(fileName: "scan.pdf"))?.id, "pdf")
    }

    func testDefaultRegistrySupportedFileExtensionsIncludePDF() {
        XCTAssertTrue(DocumentTextExtractorRegistry.supportedFileExtensions.contains("pdf"))
        XCTAssertTrue(DocumentTextExtractorRegistry.supportedFileExtensions.contains("txt"))
    }

    func testDefaultRegistrySupportedFileExtensionsMatchesExtractors() {
        let expected = PlainTextDocumentExtractor.supportedExtensions
            .union(RTFDocumentExtractor.supportedExtensions)
            .union(WordDocumentExtractor.supportedExtensions)
            .union(PDFDocumentExtractor.supportedExtensions)

        XCTAssertEqual(DocumentTextExtractorRegistry.supportedFileExtensions, expected)
    }

    func testDefaultRegistrySelectsWordExtractor() {
        let registry = DocumentTextExtractorRegistry.default

        XCTAssertEqual(registry.extractor(for: DocumentSource(fileName: "memo.docx"))?.id, "word")
        XCTAssertEqual(registry.extractor(for: DocumentSource(fileName: "legacy.doc"))?.id, "word")
    }

    func testDefaultRegistrySelectsRTFExtractor() {
        let registry = DocumentTextExtractorRegistry.default

        XCTAssertEqual(registry.extractor(for: DocumentSource(fileName: "memo.rtf"))?.id, "rtf")
    }

    func testMatchesUppercaseFileExtension() {
        let registry = DocumentTextExtractorRegistry.default

        XCTAssertEqual(registry.extractor(for: DocumentSource(fileName: "INVOICE.PDF"))?.id, "pdf")
    }

    func testReturnsNilForUnsupportedExtension() {
        let registry = DocumentTextExtractorRegistry(extractors: [
            PlainTextDocumentExtractor()
        ])

        XCTAssertNil(registry.extractor(for: DocumentSource(fileName: "scan.pdf")))
    }

    func testDefaultRegistryProcessesUnknownTextExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).tt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "Sample text".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertTrue(DocumentTextExtractorRegistry.canProcessFile(at: url))
        XCTAssertEqual(
            DocumentTextExtractorRegistry.default.extractor(
                for: DocumentSource(fileName: url.lastPathComponent, sourceURL: url)
            )?.id,
            "plain-text"
        )
    }
}

private struct StubDocumentTextExtractor: DocumentTextExtracting {
    let id: String
    let supportedFileExtensions: Set<String>

    init(id: String, extensions: Set<String>) {
        self.id = id
        self.supportedFileExtensions = extensions
    }

    func canExtract(source: DocumentSource) -> Bool {
        supportedFileExtensions.contains(source.fileExtension)
    }

    func extract(_ request: DocumentTextExtractionRequest) throws -> DocumentTextExtractionResult {
        DocumentTextExtractionResult(format: .plainText, plainText: "stub")
    }
}
