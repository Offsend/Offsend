import Foundation

public final class GGUFFileImporter: AIModelImporting, @unchecked Sendable {
    public init() {}

    public func canHandle(_ reference: AIModelImportReference) -> Bool {
        if case .ggufFile = reference { return true }
        return false
    }

    public func importModel(
        reference: AIModelImportReference,
        into directory: URL,
        credentials: AIModelCredentials,
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> AIModelImportResult {
        guard case let .ggufFile(sourceURL) = reference else {
            throw AIModelCatalogError.invalidImportReference
        }
        _ = credentials

        let fileName = sourceURL.lastPathComponent
        progress(AIModelDownloadProgress(modelID: fileName, currentFileName: fileName))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let validation = try AIModelBundleValidator.validate(directory: directory)
        try AIModelRunnableInspector.requireRunnable(validation)
        let byteSize = AIModelBundleValidator.directoryByteSize(at: directory)
        let modelID = UUID().uuidString

        progress(
            AIModelDownloadProgress(
                modelID: modelID,
                completedFiles: 1,
                totalFiles: 1,
                downloadedBytes: byteSize,
                totalBytes: byteSize
            )
        )

        let model = InstalledAIModel(
            id: modelID,
            displayName: sourceURL.deletingPathExtension().lastPathComponent,
            source: .importedFolder(originalPath: sourceURL.path),
            format: .gguf,
            localDirectoryName: modelID,
            totalByteSize: byteSize
        )
        return AIModelImportResult(model: model)
    }
}
