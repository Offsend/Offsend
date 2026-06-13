import Foundation
import DetectionCore

public struct AIModelRunnableInspection: Equatable, Sendable {
    public let isRunnable: Bool
    public let format: AIModelFormat?
    public let reason: String?

    public init(isRunnable: Bool, format: AIModelFormat? = nil, reason: String? = nil) {
        self.isRunnable = isRunnable
        self.format = format
        self.reason = reason
    }
}

public enum AIModelRunnableInspector {
    private static let safetensorsWithoutONNXReason =
        "This Hugging Face repo has safetensors weights but no onnx/ folder. Use a curated model in Settings → AI or import an ONNX bundle."
    private static let noRunnableFilesReason =
        "No runnable model files found. Offsend needs an ONNX token-classification model or a Core ML .mlpackage."
    private static let missingTokenizerReason =
        "No tokenizer.json found. Offsend needs a Hugging Face tokenizer.json next to the model weights."

    public static func inspect(validation: AIModelBundleValidation) -> AIModelRunnableInspection {
        switch validation.format {
        case .onnxTokenClassification:
            guard validation.onnxModelPath != nil else {
                return AIModelRunnableInspection(isRunnable: false, reason: noRunnableFilesReason)
            }
            guard validation.tokenizerPath != nil else {
                return AIModelRunnableInspection(isRunnable: false, reason: missingTokenizerReason)
            }
            return AIModelRunnableInspection(isRunnable: true, format: .onnxTokenClassification)
        case .coreML:
            guard validation.coreMLModelPath != nil else {
                return AIModelRunnableInspection(isRunnable: false, reason: noRunnableFilesReason)
            }
            guard validation.tokenizerPath != nil else {
                return AIModelRunnableInspection(isRunnable: false, reason: missingTokenizerReason)
            }
            return AIModelRunnableInspection(isRunnable: true, format: .coreML)
        case .huggingFaceTransformers:
            return AIModelRunnableInspection(isRunnable: false, reason: safetensorsWithoutONNXReason)
        case .gguf:
            guard validation.ggufModelPath != nil else {
                return AIModelRunnableInspection(isRunnable: false, reason: noRunnableFilesReason)
            }
            return AIModelRunnableInspection(isRunnable: true, format: .gguf)
        case .ollamaAPI:
            return AIModelRunnableInspection(isRunnable: true, format: .ollamaAPI)
        }
    }

    public static func inspectRemoteFilePaths(_ paths: [String]) -> AIModelRunnableInspection {
        let hasTokenizer = paths.contains { $0.hasSuffix("tokenizer.json") }
        if paths.contains(where: { $0.hasSuffix(".onnx") }) {
            guard hasTokenizer else {
                return AIModelRunnableInspection(isRunnable: false, reason: missingTokenizerReason)
            }
            return AIModelRunnableInspection(isRunnable: true, format: .onnxTokenClassification)
        }
        if paths.contains(where: { $0.hasSuffix(".mlpackage") }) {
            guard hasTokenizer else {
                return AIModelRunnableInspection(isRunnable: false, reason: missingTokenizerReason)
            }
            return AIModelRunnableInspection(isRunnable: true, format: .coreML)
        }
        let hasSafetensors = paths.contains {
            $0.hasSuffix(".safetensors") || $0.hasSuffix(".bin") || $0.hasSuffix(".pt")
        }
        if hasSafetensors {
            return AIModelRunnableInspection(isRunnable: false, reason: safetensorsWithoutONNXReason)
        }
        if paths.contains(where: { $0.hasSuffix(".gguf") }) {
            return AIModelRunnableInspection(isRunnable: true, format: .gguf)
        }
        return AIModelRunnableInspection(isRunnable: false, reason: noRunnableFilesReason)
    }

    public static func requireRunnable(_ validation: AIModelBundleValidation) throws {
        let inspection = inspect(validation: validation)
        guard inspection.isRunnable else {
            throw AIModelCatalogError.incompatibleModel(inspection.reason ?? noRunnableFilesReason)
        }
    }
}

public extension AIModelBundleValidation {
    var runnableInspection: AIModelRunnableInspection {
        AIModelRunnableInspector.inspect(validation: self)
    }
}
