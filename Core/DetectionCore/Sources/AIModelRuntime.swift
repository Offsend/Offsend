import Foundation

public struct AIModelBundle: Equatable, Sendable {
    public let model: InstalledAIModel
    public let directory: URL
    public let validation: AIModelBundleValidation

    public init(model: InstalledAIModel, directory: URL, validation: AIModelBundleValidation) {
        self.model = model
        self.directory = directory
        self.validation = validation
    }
}

public enum AIModelRuntimeError: Error, Equatable, Sendable {
    case unsupportedFormat(AIModelFormat)
    case modelNotLoaded
    case runtimeUnavailable(String)
    case inferenceFailed(String)
}

extension AIModelRuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "No runtime available for format: \(format.rawValue)."
        case .modelNotLoaded:
            return "AI model is not loaded."
        case .runtimeUnavailable(let message):
            return message
        case .inferenceFailed(let message):
            return message
        }
    }
}

public protocol AIModelRunning: Sendable {
    var format: AIModelFormat { get }
    func load(bundle: AIModelBundle) async throws
    func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity]
    func unload()
}

public enum AIModelRuntimeFactory: Sendable {
    public static func make(format: AIModelFormat) -> any AIModelRunning {
        switch format {
        // `.huggingFaceTransformers` is rejected by `AIModelRunnableInspector` before loading;
        // the ONNX runner is only a defensive fallback that reports a clear error.
        case .onnxTokenClassification, .huggingFaceTransformers:
            return ONNXTokenClassificationRunner()
        case .coreML:
            return CoreMLTokenClassificationRunner()
        case .gguf:
            return GGUFModelRunner()
        case .ollamaAPI:
            return OllamaAPIRunner()
        }
    }
}
