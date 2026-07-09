import Foundation
import DetectionCore

public final class AIModelImportCoordinator: Sendable {
    private let importers: [any AIModelImporting]

    public init(importers: [any AIModelImporting]? = nil) {
        self.importers = importers ?? [
            HuggingFaceModelImporter(),
            FolderModelImporter(),
            URLModelImporter(),
            ManifestModelImporter(),
            OllamaModelImporter(),
            GGUFFileImporter(),
        ]
    }

    public func importModel(
        reference: AIModelImportReference,
        credentials: AIModelCredentials = AIModelCredentials(),
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> AIModelImportResult {
        guard let importer = importers.first(where: { $0.canHandle(reference) }) else {
            throw AIModelCatalogError.invalidImportReference
        }

        let directoryName = provisionalDirectoryName(for: reference)
        try AIModelFileStore.ensureModelsDirectory()
        let directory = AIModelFileStore.modelDirectory(for: directoryName)

        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }

        let result = try await importer.importModel(
            reference: reference,
            into: directory,
            credentials: credentials,
            progress: progress
        )

        if result.model.localDirectoryName != directoryName {
            let finalDirectory = AIModelFileStore.modelDirectory(for: result.model.localDirectoryName)
            if directory.path != finalDirectory.path {
                if FileManager.default.fileExists(atPath: finalDirectory.path) {
                    try FileManager.default.removeItem(at: finalDirectory)
                }
                try FileManager.default.moveItem(at: directory, to: finalDirectory)
            }
        }

        return result
    }

    private func provisionalDirectoryName(for reference: AIModelImportReference) -> String {
        switch reference {
        case .huggingFace(let rawReference, _, _, _):
            if let repositoryID = HuggingFaceRepository.parseRepositoryID(rawReference) {
                return HuggingFaceRepository.directoryName(for: repositoryID)
            }
            return UUID().uuidString
        case .folder, .remoteURL, .ggufFile:
            return UUID().uuidString
        case .manifest(let url):
            let name = url.deletingPathExtension().lastPathComponent
            return name.isEmpty ? UUID().uuidString : name.replacingOccurrences(of: "/", with: "__")
        case .ollama(let endpoint, let modelName):
            if let url = try? OllamaClient.normalizedLocalEndpoint(endpoint),
               let modelID = try? OllamaModelImporter.modelID(endpoint: url, modelName: modelName) {
                return modelID
            }
            return UUID().uuidString
        }
    }
}
