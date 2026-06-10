import Foundation

public final class FolderModelImporter: AIModelImporting, @unchecked Sendable {
    public init() {}

    public func canHandle(_ reference: AIModelImportReference) -> Bool {
        if case .folder = reference { return true }
        return false
    }

    public func importModel(
        reference: AIModelImportReference,
        into directory: URL,
        credentials: AIModelCredentials,
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> AIModelImportResult {
        guard case let .folder(sourceURL) = reference else {
            throw AIModelCatalogError.invalidImportReference
        }
        _ = credentials

        let modelID = UUID().uuidString
        progress(AIModelDownloadProgress(modelID: modelID, currentFileName: sourceURL.lastPathComponent))

        try AIModelFileStore.copyContents(from: sourceURL, to: directory)
        let validation = try AIModelBundleValidator.validate(directory: directory)
        try AIModelRunnableInspector.requireRunnable(validation)
        let displayName = sourceURL.lastPathComponent
        let byteSize = AIModelBundleValidator.directoryByteSize(at: directory)

        progress(
            AIModelDownloadProgress(
                modelID: modelID,
                completedFiles: 1,
                totalFiles: 1,
                currentFileName: displayName,
                downloadedBytes: byteSize,
                totalBytes: byteSize
            )
        )

        let model = InstalledAIModel(
            id: modelID,
            displayName: displayName,
            source: .importedFolder(originalPath: sourceURL.path),
            format: validation.format,
            localDirectoryName: modelID,
            totalByteSize: byteSize
        )
        return AIModelImportResult(model: model)
    }
}
