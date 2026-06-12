import Foundation
import OnnxRuntimeBindings

private final class LoadedONNXNERModel: @unchecked Sendable {
    let env: ORTEnv
    let session: ORTSession
    let backend: ONNXRuntimeExecutionBackend
    let tokenizer: HFTokenizer
    let config: HFModelConfig

    init(
        env: ORTEnv,
        session: ORTSession,
        backend: ONNXRuntimeExecutionBackend,
        tokenizer: HFTokenizer,
        config: HFModelConfig
    ) {
        self.env = env
        self.session = session
        self.backend = backend
        self.tokenizer = tokenizer
        self.config = config
    }
}

/// ONNX token-classification runner for Hugging Face NER / PII models.
public final class ONNXTokenClassificationRunner: AIModelRunning, @unchecked Sendable {
    public let format: AIModelFormat = .onnxTokenClassification

    private let lock = NSLock()
    private var loaded: LoadedONNXNERModel?

    public init() {}

    public var executionBackend: ONNXRuntimeExecutionBackend? {
        lock.withLock { loaded?.backend }
    }

    public func load(bundle: AIModelBundle) async throws {
        guard bundle.validation.format == .onnxTokenClassification || bundle.validation.format == .huggingFaceTransformers else {
            throw AIModelRuntimeError.unsupportedFormat(bundle.validation.format)
        }
        guard let onnxRelativePath = bundle.validation.onnxModelPath else {
            if bundle.validation.format == .huggingFaceTransformers {
                throw AIModelRuntimeError.runtimeUnavailable(
                    "This model has safetensors weights but no ONNX export. Re-download a repo with an onnx/ folder or import an ONNX bundle."
                )
            }
            throw AIModelRuntimeError.runtimeUnavailable("No .onnx model file found in bundle.")
        }

        let modelPath = bundle.directory.appendingPathComponent(onnxRelativePath).path
        let tokenizerURL = HFTokenizer.resolveURL(in: bundle.directory, hint: bundle.validation.tokenizerPath)
        let tokenizer = try HFTokenizer(tokenizerURL: tokenizerURL)
        guard let config = HFModelConfig.load(from: bundle.directory) else {
            throw AIModelRuntimeError.inferenceFailed("Missing or invalid config.json with id2label mapping.")
        }

        let env = try ORTEnv(loggingLevel: .warning)
        let built = try ONNXRuntimeSessionBuilder.makeSession(env: env, modelPath: modelPath)

        lock.withLock {
            loaded = LoadedONNXNERModel(
                env: env,
                session: built.session,
                backend: built.backend,
                tokenizer: tokenizer,
                config: config
            )
        }
    }

    public func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity] {
        let model: LoadedONNXNERModel? = lock.withLock { loaded }
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
            try self.executeSession(tokens: tokens, model: model)
        }
    }

    public func unload() {
        lock.withLock { loaded = nil }
    }

    private func executeSession(tokens: [HFEncodedToken], model: LoadedONNXNERModel) throws -> [Float] {
        let sequenceLength = tokens.count
        let inputIDs = tokens.map(\.id)
        let attentionMask = inputIDs.map { $0 == model.tokenizer.padToken ? Int64(0) : Int64(1) }

        let shape: [NSNumber] = [1, NSNumber(value: sequenceLength)]
        let inputIDsValue = try ORTValue(
            tensorData: NSMutableData(data: ONNXTensorHelpers.dataCopiedFromArray(inputIDs)),
            elementType: .int64,
            shape: shape
        )
        let attentionValue = try ORTValue(
            tensorData: NSMutableData(data: ONNXTensorHelpers.dataCopiedFromArray(attentionMask)),
            elementType: .int64,
            shape: shape
        )

        let inputNames = try model.session.inputNames()
        var inputs: [String: ORTValue] = [:]
        for name in inputNames {
            let lowered = name.lowercased()
            if lowered.contains("input_ids") || lowered == "input" {
                inputs[name] = inputIDsValue
            } else if lowered.contains("attention") {
                inputs[name] = attentionValue
            } else if lowered.contains("token_type") {
                let tokenTypeIDs = [Int64](repeating: 0, count: sequenceLength)
                inputs[name] = try ORTValue(
                    tensorData: NSMutableData(data: ONNXTensorHelpers.dataCopiedFromArray(tokenTypeIDs)),
                    elementType: .int64,
                    shape: shape
                )
            }
        }

        guard !inputs.isEmpty else {
            throw AIModelRuntimeError.inferenceFailed("Model has no recognized inputs.")
        }

        let outputNames = Set(try model.session.outputNames())
        let outputs = try model.session.run(withInputs: inputs, outputNames: outputNames, runOptions: nil)

        let logitsOutput = outputs.first { key, _ in
            key.lowercased().contains("logit")
        }?.value ?? outputs.values.first

        guard let logitsValue = logitsOutput else {
            throw AIModelRuntimeError.inferenceFailed("Model returned no outputs.")
        }

        let tensorInfo = try logitsValue.tensorTypeAndShapeInfo()
        let rawData = try logitsValue.tensorData() as Data
        guard let floats = ONNXTensorHelpers.floatArray(from: rawData) else {
            throw AIModelRuntimeError.inferenceFailed("Could not read logits tensor.")
        }

        let shapeDims = tensorInfo.shape.map(\.intValue)
        guard shapeDims.count == 2 || shapeDims.count == 3 else {
            throw AIModelRuntimeError.inferenceFailed("Unexpected logits shape: \(shapeDims)")
        }
        return floats
    }

}
