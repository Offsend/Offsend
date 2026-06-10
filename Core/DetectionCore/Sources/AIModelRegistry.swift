import Foundation

public actor AIModelRegistry {
    private let makeRunner: @Sendable (AIModelFormat) -> any AIModelRunning
    private var runner: (any AIModelRunning)?
    private var loadedModelID: String?
    /// Chains `load` calls so two concurrent loads can't both create runners
    /// (Ollama/GGUF `load` has side effects in the daemon).
    private var pendingLoad: Task<Void, Error>?

    public init(makeRunner: @escaping @Sendable (AIModelFormat) -> any AIModelRunning = AIModelRuntimeFactory.make) {
        self.makeRunner = makeRunner
    }

    public func load(model: InstalledAIModel, directory: URL) async throws {
        let previous = pendingLoad
        let task = Task {
            // Let the previous load settle (success or failure) before starting a new one.
            try? await previous?.value
            try await self.performLoad(model: model, directory: directory)
        }
        pendingLoad = task
        defer { if pendingLoad == task { pendingLoad = nil } }
        try await task.value
    }

    private func performLoad(model: InstalledAIModel, directory: URL) async throws {
        if loadedModelID == model.id, runner != nil {
            return
        }

        let validation: AIModelBundleValidation
        if model.format == .ollamaAPI {
            validation = AIModelBundleValidation(format: .ollamaAPI)
        } else {
            validation = try AIModelBundleValidator.validate(directory: directory)
            try AIModelRunnableInspector.requireRunnable(validation)
        }
        let bundle = AIModelBundle(model: model, directory: directory, validation: validation)
        let runtimeFormat = model.format == .ollamaAPI ? model.format : validation.format
        let newRunner = makeRunner(runtimeFormat)
        try await newRunner.load(bundle: bundle)

        runner?.unload()
        runner = newRunner
        loadedModelID = model.id
    }

    public func unload() {
        runner?.unload()
        runner = nil
        loadedModelID = nil
    }

    public func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity] {
        guard let runner else {
            throw AIModelRuntimeError.modelNotLoaded
        }
        // The app keeps its own "which model is selected" state; make sure a stale
        // runner (selection changed while a scan was in flight) never answers for it.
        guard let selectedID = options.selectedAIModelID, selectedID == loadedModelID else {
            throw AIModelRuntimeError.modelNotLoaded
        }
        return try await runner.detect(text: text, options: options)
    }

    public var isLoaded: Bool {
        runner != nil
    }

    public var activeModelID: String? {
        loadedModelID
    }
}

extension AIModelRegistry: AIModelDetecting {}

public protocol AIModelDetecting: Sendable {
    func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity]
}
