import CoreML
import Foundation

private final class LoadedCoreMLNERModel: @unchecked Sendable {
    let model: MLModel
    let tokenizer: HFTokenizer
    let config: HFModelConfig

    init(
        model: MLModel,
        tokenizer: HFTokenizer,
        config: HFModelConfig
    ) {
        self.model = model
        self.tokenizer = tokenizer
        self.config = config
    }
}

/// Native Core ML token-classification runner for `.mlpackage` NER / PII models.
public final class CoreMLTokenClassificationRunner: AIModelRunning, @unchecked Sendable {
    public let format: AIModelFormat = .coreML

    private let lock = NSLock()
    private var loaded: LoadedCoreMLNERModel?

    public init() {}

    public func load(bundle: AIModelBundle) async throws {
        guard bundle.validation.format == .coreML else {
            throw AIModelRuntimeError.unsupportedFormat(bundle.validation.format)
        }
        guard let packageRelativePath = bundle.validation.coreMLModelPath else {
            throw AIModelRuntimeError.runtimeUnavailable("No .mlpackage found in model bundle.")
        }

        let packageURL = bundle.directory.appendingPathComponent(packageRelativePath)
        let tokenizerURL = HFTokenizer.resolveURL(in: bundle.directory, hint: bundle.validation.tokenizerPath)
        let tokenizer = try HFTokenizer(tokenizerURL: tokenizerURL)
        guard let config = HFModelConfig.load(from: bundle.directory) else {
            throw AIModelRuntimeError.inferenceFailed("Missing or invalid config.json with id2label mapping.")
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let model = try MLModel(contentsOf: packageURL, configuration: configuration)
        lock.withLock {
            loaded = LoadedCoreMLNERModel(
                model: model,
                tokenizer: tokenizer,
                config: config
            )
        }
    }

    public func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity] {
        let model: LoadedCoreMLNERModel? = lock.withLock { loaded }
        guard let model else {
            throw AIModelRuntimeError.modelNotLoaded
        }

        return try TokenClassificationDecoder.detect(
            text: text,
            tokenizer: model.tokenizer,
            config: model.config,
            options: options,
            maxLength: TokenClassificationDecoder.defaultMaxLength
        ) { tokens in
            try self.execute(model: model.model, tokens: tokens, padToken: model.tokenizer.padToken)
        }
    }

    public func unload() {
        lock.withLock { loaded = nil }
    }

    private func execute(model: MLModel, tokens: [HFEncodedToken], padToken: Int64) throws -> [Float] {
        let sequenceLength = tokens.count
        let inputIDs = tokens.map(\.id)
        let attentionMask = inputIDs.map { $0 == padToken ? Int64(0) : Int64(1) }

        var features: [String: MLFeatureValue] = [:]
        for (name, description) in model.modelDescription.inputDescriptionsByName {
            let lowered = name.lowercased()
            if lowered.contains("input_ids") || lowered == "input" {
                features[name] = try CoreMLMultiArrayHelpers.featureValue(
                    integers: inputIDs,
                    description: description,
                    length: sequenceLength
                )
            } else if lowered.contains("attention") {
                features[name] = try CoreMLMultiArrayHelpers.featureValue(
                    integers: attentionMask,
                    description: description,
                    length: sequenceLength
                )
            } else if lowered.contains("token_type") {
                features[name] = try CoreMLMultiArrayHelpers.featureValue(
                    integers: [Int64](repeating: 0, count: sequenceLength),
                    description: description,
                    length: sequenceLength
                )
            }
        }

        guard !features.isEmpty else {
            throw AIModelRuntimeError.inferenceFailed("Core ML model has no recognized inputs.")
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: features)
        let output = try model.prediction(from: provider)

        // `featureNames` is a Set; sort so the fallback pick is deterministic across runs.
        let outputNames = output.featureNames.sorted()
        let logitsFeature = outputNames.first { name in
            name.lowercased().contains("logit")
        }.flatMap { output.featureValue(for: $0) } ?? outputNames.first.flatMap { output.featureValue(for: $0) }

        guard let logitsFeature else {
            throw AIModelRuntimeError.inferenceFailed("Core ML model returned no logits output.")
        }

        return try CoreMLMultiArrayHelpers.floatArray(from: logitsFeature)
    }

}
