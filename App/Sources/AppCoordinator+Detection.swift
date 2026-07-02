import DetectionCore
import Foundation
import RiskScoringCore

extension AppCoordinator {
    func assessClipboardText(_ text: String) async -> (DetectionResult, RiskAssessment) {
        beginAIModelSession()
        defer { endAIModelSession() }

        await ensureAIModelLoadedForDetection()
        let options = detectionOptions()
        let engine = detectionEngine
        let risk = riskEngine
        return await Task.detached(priority: .userInitiated) {
            let detection = await engine.scan(DetectionRequest(text: text, options: options))
            return (detection, risk.assess(detection.entities))
        }.value
    }

    func runClipboardAssessment(for text: String, onComplete: @escaping @MainActor (DetectionResult, RiskAssessment) -> Void) {
        clipboardScanTask?.cancel()
        clipboardScanGeneration += 1
        let generation = clipboardScanGeneration
        clipboardScanTask = Task { [weak self] in
            guard let self else { return }
            isClipboardScanInProgress = true
            defer {
                if clipboardScanGeneration == generation {
                    isClipboardScanInProgress = false
                }
            }

            let result = await assessClipboardText(text)
            guard !Task.isCancelled else { return }
            if let aiError = result.0.aiDetectionError {
                lastStatusMessage = OffsendStrings.statusAiModelLoadFailed(aiError)
            }
            onComplete(result.0, result.1)
        }
    }
}
