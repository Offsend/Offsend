import Foundation

public final class OllamaAPIRunner: AIModelRunning, @unchecked Sendable {
    public let format: AIModelFormat = .ollamaAPI

    private let lock = NSLock()
    private var client: OllamaClient?
    private var modelName: String?

    public init() {}

    public func load(bundle: AIModelBundle) async throws {
        guard bundle.model.format == .ollamaAPI else {
            throw AIModelRuntimeError.unsupportedFormat(bundle.model.format)
        }
        guard case let .ollama(endpoint, remoteModelName) = bundle.model.source else {
            throw AIModelRuntimeError.runtimeUnavailable("Ollama model is missing endpoint metadata.")
        }

        let ollama = OllamaClient(baseURL: endpoint)
        guard try await ollama.modelExists(remoteModelName) else {
            throw OllamaClientError.modelNotFound(remoteModelName)
        }

        lock.withLock {
            client = ollama
            modelName = remoteModelName
        }
    }

    public func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity] {
        let snapshot: (OllamaClient, String)? = lock.withLock {
            guard let client, let modelName else { return nil }
            return (client, modelName)
        }
        guard let snapshot else {
            throw AIModelRuntimeError.modelNotLoaded
        }

        var entities: [SensitiveEntity] = []
        for chunk in LLMPIIExtractor.chunkText(text) {
            let prompt = LLMPIIExtractor.buildPrompt(for: chunk.substring)
            let json = try await snapshot.0.generateJSON(model: snapshot.1, prompt: prompt)
            let local = LLMPIIExtractor.parseEntities(
                jsonText: json,
                in: chunk.substring,
                options: options
            )
            entities += LLMPIIExtractor.remap(local, chunk: chunk, in: text)
        }
        return entities
    }

    public func unload() {
        lock.withLock {
            client = nil
            modelName = nil
        }
    }
}
