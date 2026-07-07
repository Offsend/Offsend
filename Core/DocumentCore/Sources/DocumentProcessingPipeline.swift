import DetectionCore
import Foundation
import MaskingCore
import RiskScoringCore

public protocol DocumentProcessing: Sendable {
    func analyze(_ request: DocumentProcessingRequest) async throws -> DocumentAnalysisResult
    func sanitize(
        _ request: DocumentProcessingRequest,
        entities: [SensitiveEntity]?
    ) async throws -> DocumentSanitizationResult
    func buildPDFRedactionPlan(
        analysis: DocumentAnalysisResult,
        pdfData: Data,
        selectedEntityIDs: Set<UUID>,
        manualRegions: [PDFRedactionRegion]
    ) throws -> PDFRedactionPlan
}

public final class DocumentProcessingPipeline: DocumentProcessing, Sendable {
    private let textExtractor: DocumentTextExtractor
    private let detector: SensitiveDataDetecting
    private let riskScorer: RiskScoring
    private let maskingEngine: TextMasking
    private let pdfRedactionPlanBuilder: PDFRedactionPlanBuilding

    public init(
        textExtractor: DocumentTextExtractor = DocumentTextExtractor(),
        detector: SensitiveDataDetecting = DetectionEngine(),
        riskScorer: RiskScoring = RiskScoringEngine(),
        maskingEngine: TextMasking = MaskingEngine(),
        pdfRedactionPlanBuilder: PDFRedactionPlanBuilding? = nil
    ) {
        self.textExtractor = textExtractor
        self.detector = detector
        self.riskScorer = riskScorer
        self.maskingEngine = maskingEngine
        self.pdfRedactionPlanBuilder = pdfRedactionPlanBuilder ?? Self.makeDefaultPDFRedactionPlanBuilder()
    }

    /// Plain-text extraction pipeline for cross-platform CLI and CI.
    public static func forCLI() -> DocumentProcessingPipeline {
        DocumentProcessingPipeline(textExtractor: .forCLI())
    }

    /// Runtime default: full document support on Apple platforms, plain text on Linux.
    public static func forRuntime() -> DocumentProcessingPipeline {
        #if os(Linux)
        return forCLI()
        #else
        return DocumentProcessingPipeline()
        #endif
    }

    static func makeDefaultPDFRedactionPlanBuilder() -> PDFRedactionPlanBuilding {
        #if canImport(PDFKit)
        return PDFRedactionPlanBuilder()
        #else
        return UnavailablePDFRedactionPlanBuilder()
        #endif
    }

    public func analyze(_ request: DocumentProcessingRequest) async throws -> DocumentAnalysisResult {
        let extracted = try textExtractor.extract(request)
        let detection = await detector.scan(
            DetectionRequest(text: extracted.plainText, options: Self.detectionOptions(for: request))
        )
        let context = DetectionContext(path: request.source.sourceURL?.path ?? request.source.fileName)
        let assessment = riskScorer.assess(detection.entities, context: context)
        return DocumentAnalysisResult(
            extracted: extracted,
            detection: detection,
            assessment: assessment
        )
    }

    public func sanitize(
        _ request: DocumentProcessingRequest,
        entities: [SensitiveEntity]? = nil
    ) async throws -> DocumentSanitizationResult {
        let analysis = try await analyze(request)
        let entitiesToMask = entities ?? analysis.detection.entities
        let masking = maskingEngine.mask(
            text: analysis.extracted.plainText,
            entities: entitiesToMask,
            ttl: request.options.mappingTTL
        )
        return DocumentSanitizationResult(
            extracted: analysis.extracted,
            detection: analysis.detection,
            assessment: analysis.assessment,
            masking: masking
        )
    }

    public func buildPDFRedactionPlan(
        analysis: DocumentAnalysisResult,
        pdfData: Data,
        selectedEntityIDs: Set<UUID>,
        manualRegions: [PDFRedactionRegion]
    ) throws -> PDFRedactionPlan {
        try pdfRedactionPlanBuilder.buildPlan(
            analysis: analysis,
            pdfData: pdfData,
            selectedEntityIDs: selectedEntityIDs,
            manualRegions: manualRegions
        )
    }

    private static func detectionOptions(for request: DocumentProcessingRequest) -> DetectionOptions {
        var options = request.options.detection
        options.maximumLength = min(
            options.maximumLength,
            request.options.maximumExtractedCharacterCount
        )
        return options
    }
}
