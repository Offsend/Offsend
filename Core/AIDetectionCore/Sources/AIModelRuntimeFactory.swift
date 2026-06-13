import DetectionCore
import Foundation

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
