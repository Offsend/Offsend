import Foundation
import DetectionCore

/// Runs local GGUF weights through a local Ollama daemon (creates a temporary Ollama model on load).
public final class GGUFModelRunner: AIModelRunning, @unchecked Sendable {
    public let format: AIModelFormat = .gguf

    private let lock = NSLock()
    private var client: OllamaClient?
    private var ollamaModelName: String?

    public init() {}

    public func load(bundle: AIModelBundle) async throws {
        guard bundle.validation.format == .gguf else {
            throw AIModelRuntimeError.unsupportedFormat(bundle.validation.format)
        }
        guard let ggufRelativePath = bundle.validation.ggufModelPath else {
            throw AIModelRuntimeError.runtimeUnavailable("No .gguf file found in model bundle.")
        }

        let ggufURL = bundle.directory.appendingPathComponent(ggufRelativePath)
        guard FileManager.default.fileExists(atPath: ggufURL.path) else {
            throw AIModelRuntimeError.runtimeUnavailable("GGUF file is missing on disk.")
        }

        let endpoint = try OllamaClient.normalizedLocalEndpoint("http://127.0.0.1:11434")
        let client = OllamaClient(baseURL: endpoint)
        let registeredName = Self.ollamaModelName(for: bundle.model.id)
        if try await !client.modelExists(registeredName) {
            try await client.createModel(name: registeredName, ggufFileURL: ggufURL)
        }

        lock.withLock {
            self.client = client
            ollamaModelName = registeredName
        }
    }

    public func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity] {
        let snapshot: (OllamaClient, String)? = lock.withLock {
            guard let client, let ollamaModelName else { return nil }
            return (client, ollamaModelName)
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
        let snapshot: (OllamaClient, String)? = lock.withLock {
            guard let client, let ollamaModelName else { return nil }
            return (client, ollamaModelName)
        }
        lock.withLock {
            client = nil
            ollamaModelName = nil
        }
        guard let snapshot else { return }
        // Best-effort cleanup of the temporary daemon model; must not block the caller.
        Task.detached {
            try? await snapshot.0.deleteModel(name: snapshot.1)
        }
    }

    static func ollamaModelName(for modelID: String) -> String {
        let sanitized = modelID
            .lowercased()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "_", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "offsend-gguf-\(sanitized)"
    }
}
