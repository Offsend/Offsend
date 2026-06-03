import DetectionCore
import Foundation
import MaskingCore
import RiskScoringCore

public protocol DocumentProcessing: Sendable {
    func analyze(_ request: DocumentProcessingRequest) throws -> DocumentAnalysisResult
    func sanitize(
        _ request: DocumentProcessingRequest,
        entities: [SensitiveEntity]?
    ) throws -> DocumentSanitizationResult
}

public final class DocumentProcessingPipeline: DocumentProcessing, @unchecked Sendable {
    private let textExtractor: DocumentTextExtractor
    private let detector: SensitiveDataDetecting
    private let riskScorer: RiskScoring
    private let maskingEngine: TextMasking

    public init(
        textExtractor: DocumentTextExtractor = DocumentTextExtractor(),
        detector: SensitiveDataDetecting = DetectionEngine(),
        riskScorer: RiskScoring = RiskScoringEngine(),
        maskingEngine: TextMasking = MaskingEngine()
    ) {
        self.textExtractor = textExtractor
        self.detector = detector
        self.riskScorer = riskScorer
        self.maskingEngine = maskingEngine
    }

    public func analyze(_ request: DocumentProcessingRequest) throws -> DocumentAnalysisResult {
        let extracted = try textExtractor.extract(request)
        let detection = detector.scan(
            DetectionRequest(text: extracted.plainText, options: Self.detectionOptions(for: request))
        )
        let assessment = riskScorer.assess(detection.entities)
        return DocumentAnalysisResult(
            extracted: extracted,
            detection: detection,
            assessment: assessment
        )
    }

    public func sanitize(
        _ request: DocumentProcessingRequest,
        entities: [SensitiveEntity]? = nil
    ) throws -> DocumentSanitizationResult {
        let analysis = try analyze(request)
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

    private static func detectionOptions(for request: DocumentProcessingRequest) -> DetectionOptions {
        var options = request.options.detection
        options.maximumLength = min(
            options.maximumLength,
            request.options.maximumExtractedCharacterCount
        )
        return options
    }
}
