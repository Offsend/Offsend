import Foundation
import DetectionCore

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
        guard Self.isSafeModelName(trimmedModel) else {
            throw AIModelCatalogError.importFailed("Ollama model name contains unsupported characters.")
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

        let modelID = try Self.modelID(endpoint: endpoint, modelName: trimmedModel)
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

    public static func modelID(endpoint: URL, modelName: String) throws -> String {
        guard isSafeModelName(modelName) else {
            throw AIModelCatalogError.importFailed("Ollama model name contains unsupported characters.")
        }
        let host = endpoint.host ?? "localhost"
        guard isSafeHostComponent(host) else {
            throw AIModelCatalogError.importFailed("Ollama endpoint host is not a safe directory name.")
        }
        let port = endpoint.port.map(String.init) ?? "11434"
        let hostSlug = host.replacingOccurrences(of: ":", with: "-")
        let slug = modelName
            .lowercased()
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let id = "ollama-\(hostSlug)-\(port)-\(slug)"
        guard isSafeDirectoryName(id) else {
            throw AIModelCatalogError.importFailed("Ollama model id is not a safe directory name.")
        }
        return id
    }

    /// Ollama names are typically `library/name:tag` or `name:tag`.
    public static func isSafeModelName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(".."), !trimmed.contains("\0") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-/:"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isSafeHostComponent(_ host: String) -> Bool {
        // Allow IPv6 literals (`::1`) — colons are later flattened for the directory name.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:"))
        return !host.isEmpty && host.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isSafeDirectoryName(_ name: String) -> Bool {
        let components = (name as NSString).pathComponents
        return components.count == 1 && components[0] != "." && components[0] != ".."
            && !name.contains("/") && !name.hasPrefix("~")
    }
}

struct OllamaInstalledMetadata: Codable, Equatable {
    let endpoint: URL
    let modelName: String
}
