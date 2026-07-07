import XCTest
@testable import DocumentCore

final class DocumentTextExtractorRegistryCLITests: XCTestCase {
    func testCLIDefaultRegistrySupportsPlainTextOnly() {
        let registry = DocumentTextExtractorRegistry.cliDefault

        XCTAssertEqual(registry.extractor(for: DocumentSource(fileName: "notes.txt"))?.id, "plain-text")
        XCTAssertEqual(registry.extractor(for: DocumentSource(fileName: "main.swift"))?.id, "plain-text")
        XCTAssertNil(registry.extractor(for: DocumentSource(fileName: "scan.pdf")))
        XCTAssertNil(registry.extractor(for: DocumentSource(fileName: "memo.docx")))
        XCTAssertNil(registry.extractor(for: DocumentSource(fileName: "memo.rtf")))
    }

    func testCLIDefaultRegistryProcessesUnknownTextExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).tt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "Sample text".write(to: url, atomically: true, encoding: .utf8)

        let registry = DocumentTextExtractorRegistry.cliDefault
        let source = DocumentSource(fileName: url.lastPathComponent, sourceURL: url)

        XCTAssertEqual(registry.extractor(for: source)?.id, "plain-text")
    }
}

final class DocumentProcessingPipelineCLITests: XCTestCase {
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample-invoice.txt")
    }

    func testForCLIAnalyzesPlainTextFixture() async throws {
        let pipeline = DocumentProcessingPipeline.forCLI()
        let request = try DocumentProcessingRequest(fileURL: fixtureURL)

        let result = try await pipeline.analyze(request)

        XCTAssertEqual(result.extracted.extractorID, "plain-text")
        XCTAssertTrue(result.detection.entities.contains { $0.type == .email })
    }

    func testForCLIBuildPDFRedactionPlanIsUnavailable() async throws {
        let pipeline = DocumentProcessingPipeline.forCLI()
        let request = try DocumentProcessingRequest(fileURL: fixtureURL)
        let analysis = try await pipeline.analyze(request)

        XCTAssertThrowsError(
            try pipeline.buildPDFRedactionPlan(
                analysis: analysis,
                pdfData: Data(),
                selectedEntityIDs: [],
                manualRegions: []
            )
        ) { error in
            XCTAssertEqual(error as? PDFRedactionError, .unsupportedFormat)
        }
    }
}
