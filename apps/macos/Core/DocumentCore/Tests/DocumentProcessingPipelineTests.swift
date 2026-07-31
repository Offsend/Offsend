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

    private func makePipeline(
        textExtractor: DocumentTextExtractor = DocumentTextExtractor()
    ) -> DocumentProcessingPipeline {
        DocumentProcessingPipeline(
            textExtractor: textExtractor,
            detector: SubstringDetector(),
            riskScorer: DocsAwareRiskScorer(),
            maskingEngine: PlaceholderMasking()
        )
    }

    func testAnalyzeExtractsAndScoresFixture() async throws {
        let pipeline = makePipeline()
        let request = try DocumentProcessingRequest(fileURL: fixtureURL)

        let result = try await pipeline.analyze(request)

        XCTAssertEqual(result.extracted.extractorID, "plain-text")
        XCTAssertEqual(result.extracted.source.fileName, "sample-invoice.txt")
        XCTAssertTrue(result.detection.entities.contains { $0.type == .email })
        XCTAssertTrue(result.detection.entities.contains { $0.type == .contractId })
        XCTAssertEqual(result.assessment.level, .medium)
        XCTAssertEqual(result.assessment.recommendedAction, .warn)
        XCTAssertFalse(result.assessment.hasCriticalSecret)
    }

    func testSanitizeMasksDetectedEntities() async throws {
        let pipeline = makePipeline()
        let request = try DocumentProcessingRequest(fileURL: fixtureURL)

        let result = try await pipeline.sanitize(request)

        XCTAssertTrue(result.masking.maskedText.contains("{{EMAIL_1}}"))
        XCTAssertTrue(result.masking.maskedText.contains("{{CONTRACT_1}}"))
        XCTAssertEqual(result.masking.mapping["{{EMAIL_1}}"], "ivan@acme.com")
    }

    func testSanitizeUsesEntityOverride() async throws {
        let pipeline = makePipeline()
        let request = try DocumentProcessingRequest(fileURL: fixtureURL)
        let analysis = try await pipeline.analyze(request)
        let emailOnly = analysis.detection.entities.filter { $0.type == .email }

        let result = try await pipeline.sanitize(request, entities: emailOnly)

        XCTAssertTrue(result.masking.maskedText.contains("{{EMAIL_1}}"))
        XCTAssertTrue(result.masking.maskedText.contains("CN-4812"))
    }

    func testAnalyzeExtractsDocxAsPDF() async throws {
        let docxData = try WordTestFixtures.makeDocx(containing: "Contact ivan@acme.com for invoice CN-4812")
        let request = DocumentProcessingRequest(
            data: docxData,
            source: DocumentSource(fileName: "scan.docx")
        )
        let pipeline = makePipeline()

        let result = try await pipeline.analyze(request)

        XCTAssertEqual(result.extracted.extractorID, "word")
        XCTAssertEqual(result.extracted.format, .pdf)
        XCTAssertNotNil(result.extracted.pdfData)
        XCTAssertTrue(result.extracted.plainText.contains("ivan@acme.com"))
        XCTAssertTrue(result.detection.entities.contains { $0.type == .email })
    }

    func testBuildsPDFRedactionPlanForConvertedDocx() async throws {
        let text = "Send payment to ivan@acme.com"
        let docxData = try WordTestFixtures.makeDocx(containing: text)
        let pdfData = try AppKitWordDocumentToPDFConverter().convert(data: docxData, fileExtension: "docx")
        let pipeline = makePipeline()
        let request = DocumentProcessingRequest(
            data: docxData,
            source: DocumentSource(fileName: "invoice.docx")
        )

        let analysis = try await pipeline.analyze(request)
        let entityIDs = Set(analysis.detection.entities.map(\.id))

        let plan = try pipeline.buildPDFRedactionPlan(
            analysis: analysis,
            pdfData: pdfData,
            selectedEntityIDs: entityIDs,
            manualRegions: []
        )

        XCTAssertFalse(plan.regions.isEmpty)
        XCTAssertTrue(plan.unresolvedValues.isEmpty)
    }

    func testSanitizeMasksDetectedEntitiesInDocx() async throws {
        let docxData = try WordTestFixtures.makeDocx(containing: "Send invoice to ivan@acme.com")
        let request = DocumentProcessingRequest(
            data: docxData,
            source: DocumentSource(fileName: "invoice.docx")
        )
        let pipeline = makePipeline()

        let result = try await pipeline.sanitize(request)

        XCTAssertEqual(result.extracted.format, .pdf)
        XCTAssertTrue(result.masking.maskedText.contains("{{EMAIL_1}}"))
        XCTAssertEqual(result.masking.mapping["{{EMAIL_1}}"], "ivan@acme.com")
    }

    func testExportsRedactedPDFFromDocx() async throws {
        let secret = "ivan@acme.com"
        let docxData = try WordTestFixtures.makeDocx(containing: "Send payment to \(secret)")
        let pipeline = makePipeline()
        let request = DocumentProcessingRequest(
            data: docxData,
            source: DocumentSource(fileName: "invoice.docx")
        )

        let analysis = try await pipeline.analyze(request)
        guard let pdfData = analysis.extracted.pdfData else {
            return XCTFail("Expected converted PDF data")
        }

        let session = PDFRedactionSession(
            sourceData: pdfData,
            analysis: analysis,
            selectedEntityIDs: Set(analysis.detection.entities.map(\.id))
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: destination) }

        let result = try PDFRedactionExporter().export(session: session, to: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(
            WordTestFixtures.extractPlainText(from: result.redactedData)
                .localizedCaseInsensitiveContains(secret)
        )
    }

    func testAnalyzeExtractsPDF() async throws {
        let pipeline = makePipeline()
        let pdfData = PDFTestFixtures.makePDF(containing: "Contact ivan@acme.com for invoice CN-4812")
        let request = DocumentProcessingRequest(
            data: pdfData,
            source: DocumentSource(fileName: "invoice.pdf")
        )

        let result = try await pipeline.analyze(request)

        XCTAssertEqual(result.extracted.extractorID, "pdf")
        XCTAssertEqual(result.extracted.format, DocumentFormat.pdf)
        XCTAssertTrue(result.extracted.plainText.contains("ivan@acme.com"))
        XCTAssertTrue(result.detection.entities.contains { $0.type == .email })
    }

    func testSanitizeMasksDetectedEntitiesInPDF() async throws {
        let pipeline = makePipeline()
        let pdfData = PDFTestFixtures.makePDF(containing: "Send invoice to ivan@acme.com")
        let request = DocumentProcessingRequest(
            data: pdfData,
            source: DocumentSource(fileName: "invoice.pdf")
        )

        let result = try await pipeline.sanitize(request)

        XCTAssertTrue(result.masking.maskedText.contains("{{EMAIL_1}}"))
        XCTAssertEqual(result.masking.mapping["{{EMAIL_1}}"], "ivan@acme.com")
    }

    func testRejectsInvalidPDF() async {
        let pipeline = makePipeline()
        let request = DocumentProcessingRequest(
            data: Data("not-a-pdf".utf8),
            source: DocumentSource(fileName: "broken.pdf")
        )

        do {
            _ = try await pipeline.analyze(request)
            XCTFail("Expected invalidPDF error")
        } catch {
            XCTAssertEqual(error as? DocumentProcessingError, .invalidPDF)
        }
    }

    func testAnalyzesPDFWithoutExtractableText() async throws {
        let pipeline = makePipeline()
        let request = DocumentProcessingRequest(
            data: PDFTestFixtures.makeEmptyPDF(),
            source: DocumentSource(fileName: "blank.pdf")
        )

        let result = try await pipeline.analyze(request)

        XCTAssertEqual(result.extracted.format, DocumentFormat.pdf)
        XCTAssertTrue(result.extracted.plainText.isEmpty)
        XCTAssertTrue(result.detection.entities.isEmpty)
    }

    func testTruncatesExtractedPDFTextBeforeDetection() async throws {
        let text = String(repeating: "a", count: 30) + " ivan@acme.com"
        let pipeline = makePipeline()
        let request = DocumentProcessingRequest(
            data: PDFTestFixtures.makePDF(containing: text),
            source: DocumentSource(fileName: "long.pdf"),
            options: DocumentProcessingOptions(maximumExtractedCharacterCount: 20)
        )

        let result = try await pipeline.analyze(request)

        XCTAssertTrue(result.extracted.wasTruncated)
        XCTAssertFalse(result.detection.entities.contains { $0.type == .email })
    }

    func testRejectsOversizedFile() async {
        let request = DocumentProcessingRequest(
            data: Data(repeating: 0x41, count: 20),
            source: DocumentSource(fileName: "large.txt"),
            options: DocumentProcessingOptions(maximumFileByteCount: 10)
        )
        let pipeline = makePipeline()

        do {
            _ = try await pipeline.analyze(request)
            XCTFail("Expected fileTooLarge error")
        } catch {
            XCTAssertEqual(error as? DocumentProcessingError, .fileTooLarge(byteCount: 20, maximumByteCount: 10))
        }
    }

    func testTruncatesExtractedTextBeforeDetection() async throws {
        let text = String(repeating: "a", count: 30) + " ivan@acme.com"
        let request = DocumentProcessingRequest(
            data: Data(text.utf8),
            source: DocumentSource(fileName: "long.txt"),
            options: DocumentProcessingOptions(maximumExtractedCharacterCount: 20)
        )
        let pipeline = makePipeline()

        let result = try await pipeline.analyze(request)

        XCTAssertTrue(result.extracted.wasTruncated)
        XCTAssertTrue(result.extracted.warnings.contains {
            $0 == .textTruncated(originalCharacterCount: text.trimmingCharacters(in: .whitespacesAndNewlines).count, maximumCharacterCount: 20)
        })
        XCTAssertFalse(result.detection.entities.contains { $0.type == .email })
    }

    func testUsesInjectedDependencies() async throws {
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

        let result = try await pipeline.sanitize(request)

        XCTAssertEqual(result.extracted.plainText, "stubbed document")
        XCTAssertEqual(result.detection.entities.count, 1)
        XCTAssertEqual(result.assessment.level, .high)
        XCTAssertEqual(result.masking.maskedText, "masked")
    }
}

// MARK: - Test doubles (detection/mask/risk live in Rust for production)

/// Finds a few well-known substrings so DocumentCore tests do not depend on Swift DetectionEngine.
private struct SubstringDetector: SensitiveDataDetecting {
    private let needles: [(SensitiveEntityType, String)] = [
        (.email, "ivan@acme.com"),
        (.contractId, "CN-4812"),
    ]

    func scan(_ request: DetectionRequest) async -> DetectionResult {
        let text = request.text
        var entities: [SensitiveEntity] = []
        for (type, needle) in needles {
            guard let range = text.range(of: needle) else { continue }
            entities.append(
                SensitiveEntity(
                    type: type,
                    range: range,
                    value: needle,
                    confidence: 1,
                    source: .regex
                )
            )
        }
        return DetectionResult(
            entities: entities,
            scannedText: text,
            wasTruncated: false,
            scannedCharacterCount: text.count
        )
    }
}

private struct DocsAwareRiskScorer: RiskScoring {
    func assess(_ entities: [SensitiveEntity], context: DetectionContext) -> RiskAssessment {
        guard !entities.isEmpty else {
            return RiskAssessment(score: 0, level: .low, recommendedAction: .allow, hasCriticalSecret: false)
        }
        if context.sensitivity == .docsOrTests {
            return RiskAssessment(score: 75, level: .medium, recommendedAction: .warn, hasCriticalSecret: false)
        }
        return RiskAssessment(score: 60, level: .high, recommendedAction: .mask, hasCriticalSecret: false)
    }
}

private struct PlaceholderMasking: TextMasking {
    func mask(text: String, entities: [SensitiveEntity], ttl: MappingTTL) -> MaskingResult {
        let ordered = entities.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var counters: [String: Int] = [:]
        var placeholderByValue: [String: String] = [:]
        var replacements: [(range: Range<String.Index>, placeholder: String)] = []
        var coveredUpperBound: String.Index?

        for entity in ordered {
            guard entity.range.lowerBound >= text.startIndex,
                  entity.range.upperBound <= text.endIndex,
                  text[entity.range] == entity.value else { continue }
            if let upper = coveredUpperBound, entity.range.lowerBound < upper { continue }

            let placeholder: String
            if let existing = placeholderByValue[entity.value] {
                placeholder = existing
            } else {
                let prefix = entity.type.placeholderPrefix
                let next = (counters[prefix] ?? 0) + 1
                counters[prefix] = next
                placeholder = "{{\(prefix)_\(next)}}"
                placeholderByValue[entity.value] = placeholder
            }
            replacements.append((entity.range, placeholder))
            coveredUpperBound = Swift.max(coveredUpperBound ?? entity.range.upperBound, entity.range.upperBound)
        }

        var maskedText = text
        for replacement in replacements.reversed() {
            maskedText.replaceSubrange(replacement.range, with: replacement.placeholder)
        }
        let mapping = Dictionary(uniqueKeysWithValues: placeholderByValue.map { ($0.value, $0.key) })
        let retention: MaskingResult.Retention = ttl.interval
            .map { .expiring(Date().addingTimeInterval($0)) } ?? .ephemeral
        return MaskingResult(maskedText: maskedText, mapping: mapping, retention: retention)
    }

    func restore(text: String, mapping: [String: String]) -> String {
        mapping.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
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
    func scan(_ request: DetectionRequest) async -> DetectionResult {
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
    func assess(_ entities: [SensitiveEntity], context: DetectionContext) -> RiskAssessment {
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
