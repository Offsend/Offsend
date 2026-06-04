import DetectionCore
import MaskingCore
import RiskScoringCore
import XCTest
@testable import DocumentCore

final class DocumentProcessingPipelineTests: XCTestCase {
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample-invoice.txt")
    }

    func testAnalyzeExtractsAndScoresFixture() throws {
        let pipeline = DocumentProcessingPipeline()
        let request = try DocumentProcessingRequest(fileURL: fixtureURL)

        let result = try pipeline.analyze(request)

        XCTAssertEqual(result.extracted.extractorID, "plain-text")
        XCTAssertEqual(result.extracted.source.fileName, "sample-invoice.txt")
        XCTAssertTrue(result.detection.entities.contains { $0.type == .email })
        XCTAssertTrue(result.detection.entities.contains { $0.type == .contractId })
        XCTAssertNotEqual(result.assessment.recommendedAction, .allow)
    }

    func testSanitizeMasksDetectedEntities() throws {
        let pipeline = DocumentProcessingPipeline()
        let request = try DocumentProcessingRequest(fileURL: fixtureURL)

        let result = try pipeline.sanitize(request)

        XCTAssertTrue(result.masking.maskedText.contains("{{EMAIL_1}}"))
        XCTAssertTrue(result.masking.maskedText.contains("{{CONTRACT_1}}"))
        XCTAssertEqual(result.masking.mapping["{{EMAIL_1}}"], "ivan@acme.com")
    }

    func testSanitizeUsesEntityOverride() throws {
        let pipeline = DocumentProcessingPipeline()
        let request = try DocumentProcessingRequest(fileURL: fixtureURL)
        let analysis = try pipeline.analyze(request)
        let emailOnly = analysis.detection.entities.filter { $0.type == .email }

        let result = try pipeline.sanitize(request, entities: emailOnly)

        XCTAssertTrue(result.masking.maskedText.contains("{{EMAIL_1}}"))
        XCTAssertTrue(result.masking.maskedText.contains("CN-4812"))
    }

    func testRejectsUnsupportedFormat() {
        let request = DocumentProcessingRequest(
            data: Data("binary".utf8),
            source: DocumentSource(fileName: "scan.docx")
        )
        let pipeline = DocumentProcessingPipeline()

        XCTAssertThrowsError(try pipeline.analyze(request)) { error in
            XCTAssertEqual(error as? DocumentProcessingError, .unsupportedFormat(fileExtension: "docx"))
        }
    }

    func testAnalyzeExtractsPDF() throws {
        let pipeline = DocumentProcessingPipeline()
        let pdfData = PDFTestFixtures.makePDF(containing: "Contact ivan@acme.com for invoice CN-4812")
        let request = DocumentProcessingRequest(
            data: pdfData,
            source: DocumentSource(fileName: "invoice.pdf")
        )

        let result = try pipeline.analyze(request)

        XCTAssertEqual(result.extracted.extractorID, "pdf")
        XCTAssertEqual(result.extracted.format, DocumentFormat.pdf)
        XCTAssertTrue(result.extracted.plainText.contains("ivan@acme.com"))
        XCTAssertTrue(result.detection.entities.contains { $0.type == .email })
    }

    func testSanitizeMasksDetectedEntitiesInPDF() throws {
        let pipeline = DocumentProcessingPipeline()
        let pdfData = PDFTestFixtures.makePDF(containing: "Send invoice to ivan@acme.com")
        let request = DocumentProcessingRequest(
            data: pdfData,
            source: DocumentSource(fileName: "invoice.pdf")
        )

        let result = try pipeline.sanitize(request)

        XCTAssertTrue(result.masking.maskedText.contains("{{EMAIL_1}}"))
        XCTAssertEqual(result.masking.mapping["{{EMAIL_1}}"], "ivan@acme.com")
    }

    func testRejectsInvalidPDF() {
        let pipeline = DocumentProcessingPipeline()
        let request = DocumentProcessingRequest(
            data: Data("not-a-pdf".utf8),
            source: DocumentSource(fileName: "broken.pdf")
        )

        XCTAssertThrowsError(try pipeline.analyze(request)) { error in
            XCTAssertEqual(
                error as? DocumentProcessingError,
                .invalidPDF
            )
        }
    }

    func testAnalyzesPDFWithoutExtractableText() throws {
        let pipeline = DocumentProcessingPipeline()
        let request = DocumentProcessingRequest(
            data: PDFTestFixtures.makeEmptyPDF(),
            source: DocumentSource(fileName: "blank.pdf")
        )

        let result = try pipeline.analyze(request)

        XCTAssertEqual(result.extracted.format, DocumentFormat.pdf)
        XCTAssertTrue(result.extracted.plainText.isEmpty)
        XCTAssertTrue(result.detection.entities.isEmpty)
    }

    func testTruncatesExtractedPDFTextBeforeDetection() throws {
        let text = String(repeating: "a", count: 30) + " ivan@acme.com"
        let pipeline = DocumentProcessingPipeline()
        let request = DocumentProcessingRequest(
            data: PDFTestFixtures.makePDF(containing: text),
            source: DocumentSource(fileName: "long.pdf"),
            options: DocumentProcessingOptions(maximumExtractedCharacterCount: 20)
        )

        let result = try pipeline.analyze(request)

        XCTAssertTrue(result.extracted.wasTruncated)
        XCTAssertFalse(result.detection.entities.contains { $0.type == .email })
    }

    func testRejectsOversizedFile() {
        let request = DocumentProcessingRequest(
            data: Data(repeating: 0x41, count: 20),
            source: DocumentSource(fileName: "large.txt"),
            options: DocumentProcessingOptions(maximumFileByteCount: 10)
        )
        let pipeline = DocumentProcessingPipeline()

        XCTAssertThrowsError(try pipeline.analyze(request)) { error in
            XCTAssertEqual(error as? DocumentProcessingError, .fileTooLarge(byteCount: 20, maximumByteCount: 10))
        }
    }

    func testTruncatesExtractedTextBeforeDetection() throws {
        let text = String(repeating: "a", count: 30) + " ivan@acme.com"
        let request = DocumentProcessingRequest(
            data: Data(text.utf8),
            source: DocumentSource(fileName: "long.txt"),
            options: DocumentProcessingOptions(maximumExtractedCharacterCount: 20)
        )
        let pipeline = DocumentProcessingPipeline()

        let result = try pipeline.analyze(request)

        XCTAssertTrue(result.extracted.wasTruncated)
        XCTAssertTrue(result.extracted.warnings.contains {
            $0 == .textTruncated(originalCharacterCount: text.trimmingCharacters(in: .whitespacesAndNewlines).count, maximumCharacterCount: 20)
        })
        XCTAssertFalse(result.detection.entities.contains { $0.type == .email })
    }

    func testUsesInjectedDependencies() throws {
        let stubExtractor = DocumentTextExtractor(registry: StubRegistry())
        let pipeline = DocumentProcessingPipeline(
            textExtractor: stubExtractor,
            detector: StubDetector(),
            riskScorer: StubRiskScorer(),
            maskingEngine: StubMaskingEngine()
        )
        let request = DocumentProcessingRequest(
            data: Data("ignored".utf8),
            source: DocumentSource(fileName: "stub.txt")
        )

        let result = try pipeline.sanitize(request)

        XCTAssertEqual(result.extracted.plainText, "stubbed document")
        XCTAssertEqual(result.detection.entities.count, 1)
        XCTAssertEqual(result.assessment.level, .high)
        XCTAssertEqual(result.masking.maskedText, "masked")
    }
}

private struct StubRegistry: DocumentTextExtractorSelecting {
    func extractor(for source: DocumentSource) -> (any DocumentTextExtracting)? {
        StubPlainExtractor()
    }
}

private struct StubPlainExtractor: DocumentTextExtracting {
    let id = "stub"
    let supportedFileExtensions: Set<String> = ["txt"]

    func canExtract(source: DocumentSource) -> Bool { true }

    func extract(_ request: DocumentTextExtractionRequest) throws -> DocumentTextExtractionResult {
        DocumentTextExtractionResult(format: .plainText, plainText: "stubbed document")
    }
}

private struct StubDetector: SensitiveDataDetecting {
    func scan(_ request: DetectionRequest) -> DetectionResult {
        let text = request.text
        let range = text.startIndex..<text.endIndex
        return DetectionResult(
            entities: [
                SensitiveEntity(
                    type: .email,
                    range: range,
                    value: text,
                    confidence: 1,
                    source: .regex
                )
            ],
            scannedText: text,
            wasTruncated: false,
            scannedCharacterCount: text.count
        )
    }
}

private struct StubRiskScorer: RiskScoring {
    func assess(_ entities: [SensitiveEntity]) -> RiskAssessment {
        RiskAssessment(score: 60, level: .high, recommendedAction: .mask, hasCriticalSecret: false)
    }
}

private struct StubMaskingEngine: TextMasking {
    func mask(text: String, entities: [SensitiveEntity], ttl: MappingTTL) -> MaskingResult {
        MaskingResult(maskedText: "masked", mapping: ["{{EMAIL_1}}": text], retention: .ephemeral)
    }

    func restore(text: String, mapping: [String: String]) -> String {
        text
    }
}
