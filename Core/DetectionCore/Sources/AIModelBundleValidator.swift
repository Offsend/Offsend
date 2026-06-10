import Foundation

public struct AIModelBundleValidation: Equatable, Sendable {
    public let format: AIModelFormat
    public let onnxModelPath: String?
    public let coreMLModelPath: String?
    public let tokenizerPath: String?
    public let ggufModelPath: String?

    public init(
        format: AIModelFormat,
        onnxModelPath: String? = nil,
        coreMLModelPath: String? = nil,
        tokenizerPath: String? = nil,
        ggufModelPath: String? = nil
    ) {
        self.format = format
        self.onnxModelPath = onnxModelPath
        self.coreMLModelPath = coreMLModelPath
        self.tokenizerPath = tokenizerPath
        self.ggufModelPath = ggufModelPath
    }
}

public enum AIModelBundleValidator {
    private static let expectedFilesHint =
        "Expected: *.onnx + tokenizer.json, *.mlpackage, config.json + *.safetensors, or *.gguf."

    public static func validate(directory: URL) throws -> AIModelBundleValidation {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AIModelCatalogError.unsupportedFormat("Could not read model directory.")
        }

        var relativePaths: [String] = []
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        for case let itemURL as URL in enumerator {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let isRegularFile = (try? itemURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            guard isDirectory || isRegularFile else { continue }

            let path = itemURL.path
            let relative: String
            if path.hasPrefix(prefix) {
                relative = String(path.dropFirst(prefix.count))
            } else {
                relative = itemURL.lastPathComponent
            }
            relativePaths.append(relative)
        }

        if let packagePath = relativePaths.first(where: { $0.hasSuffix(".mlpackage") }) {
            return AIModelBundleValidation(
                format: .coreML,
                coreMLModelPath: packagePath,
                tokenizerPath: tokenizerRelativePath(in: relativePaths)
            )
        }

        if let onnxPath = preferredONNXPath(in: relativePaths) {
            return AIModelBundleValidation(
                format: .onnxTokenClassification,
                onnxModelPath: onnxPath,
                tokenizerPath: tokenizerRelativePath(in: relativePaths)
            )
        }

        let hasConfig = relativePaths.contains { $0.hasSuffix("config.json") }
        let hasSafetensors = relativePaths.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".bin") }

        if hasConfig, hasSafetensors {
            return AIModelBundleValidation(format: .huggingFaceTransformers)
        }

        if let ggufPath = relativePaths.first(where: { $0.hasSuffix(".gguf") }) {
            return AIModelBundleValidation(format: .gguf, ggufModelPath: ggufPath)
        }

        if relativePaths.contains("ollama.json") {
            return AIModelBundleValidation(format: .ollamaAPI)
        }

        throw AIModelCatalogError.unsupportedFormat("Unrecognized model bundle. \(expectedFilesHint)")
    }

    public static func directoryByteSize(at directory: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Repos often ship several ONNX variants (`model.onnx`, `model_int8.onnx`, `model_quantized.onnx`).
    /// Pick deterministically and prefer smaller quantized weights for on-device latency.
    static func preferredONNXPath(in relativePaths: [String]) -> String? {
        let candidates = relativePaths.filter { $0.hasSuffix(".onnx") }
        guard !candidates.isEmpty else { return nil }

        func rank(_ path: String) -> Int {
            let name = (path as NSString).lastPathComponent.lowercased()
            if name.contains("int8") { return 0 }
            if name.contains("uint8") { return 1 }
            if name.contains("quantized") || name.contains("quant") { return 2 }
            return 5
        }

        return candidates.min { lhs, rhs in
            let lhsRank = rank(lhs)
            let rhsRank = rank(rhs)
            return lhsRank == rhsRank ? lhs < rhs : lhsRank < rhsRank
        }
    }

    /// Only `tokenizer.json` counts: it is the single format `HFTokenizer` can actually load.
    static func tokenizerRelativePath(in relativePaths: [String]) -> String? {
        relativePaths.first { $0.hasSuffix("tokenizer.json") }
    }
}
