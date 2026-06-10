import DetectionCore
import DocumentCore
import Foundation
import MaskingCore

extension AppCoordinator {
    func documentProcessingOptions() -> DocumentProcessingOptions {
        DocumentProcessingOptions(
            detection: DetectionOptions(
                enabledTypes: settings.enabledDetectors,
                customDictionaries: tariffFeatures.customDictionaries ? customDictionaries : []
            ),
            mappingTTL: MappingTTL.effective(
                settings.mappingTTL,
                extendedTTLAllowed: allowsExtendedMappingTTL
            ),
            maximumFileByteCount: documentMaximumFileByteCount
        )
    }

    func analyzeDocument(at fileURL: URL) async throws -> DocumentAnalysisResult {
        let request = try DocumentProcessingRequest(
            fileURL: fileURL.standardizedFileURL,
            options: documentProcessingOptions()
        )
        let detector = detectionEngine
        let riskScorer = riskEngine
        let maskingEngine = maskingEngine
        return try await Task.detached {
            try DocumentProcessingPipeline(
                detector: detector,
                riskScorer: riskScorer,
                maskingEngine: maskingEngine
            ).analyze(request)
        }.value
    }

    func sanitizeDocument(at fileURL: URL, entities: [SensitiveEntity]?) async throws -> DocumentSanitizationResult {
        let request = try DocumentProcessingRequest(
            fileURL: fileURL.standardizedFileURL,
            options: documentProcessingOptions()
        )
        let detector = detectionEngine
        let riskScorer = riskEngine
        let maskingEngine = maskingEngine
        return try await Task.detached {
            try DocumentProcessingPipeline(
                detector: detector,
                riskScorer: riskScorer,
                maskingEngine: maskingEngine
            ).sanitize(request, entities: entities)
        }.value
    }

    func previewSanitizedDocument(
        from analysis: DocumentAnalysisResult,
        entities: [SensitiveEntity]
    ) async -> DocumentSanitizationResult {
        let maskingEngine = maskingEngine
        let ttl = documentProcessingOptions().mappingTTL
        return await Task.detached {
            DocumentSanitizationResult(
                extracted: analysis.extracted,
                detection: analysis.detection,
                assessment: analysis.assessment,
                masking: maskingEngine.mask(
                    text: analysis.extracted.plainText,
                    entities: entities,
                    ttl: ttl
                )
            )
        }.value
    }

    func copySanitizedDocument(_ result: DocumentSanitizationResult) {
        if result.masking.shouldPersist {
            try? store.saveMapping(result.masking)
            try? refreshMappingSummaries()
        }
        clipboardService.writeString(result.masking.maskedText)
        analytics.track(.maskApplied)
        lastStatusMessage = OffsendStrings.statusDocumentSafeTextCopied
    }

    func exportSanitizedDocument(_ result: DocumentSanitizationResult, to destinationURL: URL) throws {
        if result.masking.shouldPersist {
            try store.saveMapping(result.masking)
            try refreshMappingSummaries()
        }
        try result.masking.maskedText.write(to: destinationURL, atomically: true, encoding: .utf8)
        analytics.track(.maskApplied)
        lastStatusMessage = OffsendStrings.statusDocumentSafeTextSaved(destinationURL.lastPathComponent)
    }

    func openDocumentSanitize(for url: URL, source: String) {
        openPrepare(for: url, source: source)
    }

    func recordDocumentSanitizeOpened(source: String) {
        analytics.track(.documentSanitizeOpened(source: source))
    }
}
