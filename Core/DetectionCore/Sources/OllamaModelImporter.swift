import Foundation

public final class OllamaModelImporter: AIModelImporting, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func canHandle(_ reference: AIModelImportReference) -> Bool {
        if case .ollama = reference { return true }
        return false
    }

    public func importModel(
        reference: AIModelImportReference,
        into directory: URL,
        credentials: AIModelCredentials,
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> AIModelImportResult {
        guard case let .ollama(rawEndpoint, modelName) = reference else {
            throw AIModelCatalogError.invalidImportReference
        }
        _ = credentials

        let endpoint = try OllamaClient.normalizedLocalEndpoint(rawEndpoint)
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw AIModelCatalogError.importFailed("Choose an Ollama model name.")
        }

        progress(AIModelDownloadProgress(modelID: trimmedModel, currentFileName: trimmedModel))

        let client = OllamaClient(baseURL: endpoint, session: session)
        guard try await client.modelExists(trimmedModel) else {
            throw OllamaClientError.modelNotFound(trimmedModel)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let metadata = OllamaInstalledMetadata(endpoint: endpoint, modelName: trimmedModel)
        let metadataURL = directory.appendingPathComponent("ollama.json")
        try JSONEncoder().encode(metadata).write(to: metadataURL)

        let modelID = Self.modelID(endpoint: endpoint, modelName: trimmedModel)
        let model = InstalledAIModel(
            id: modelID,
            displayName: "\(trimmedModel) (Ollama)",
            source: .ollama(endpoint: endpoint, modelName: trimmedModel),
            format: .ollamaAPI,
            localDirectoryName: modelID,
            totalByteSize: 0
        )

        progress(
            AIModelDownloadProgress(
                modelID: modelID,
                completedFiles: 1,
                totalFiles: 1,
                currentFileName: trimmedModel
            )
        )
        return AIModelImportResult(model: model)
    }

    public static func modelID(endpoint: URL, modelName: String) -> String {
        let host = endpoint.host ?? "localhost"
        let port = endpoint.port.map(String.init) ?? "11434"
        let slug = modelName
            .lowercased()
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return "ollama-\(host)-\(port)-\(slug)"
    }
}

struct OllamaInstalledMetadata: Codable, Equatable {
    let endpoint: URL
    let modelName: String
}
