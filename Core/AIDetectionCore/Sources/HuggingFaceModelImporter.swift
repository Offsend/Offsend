import Foundation
import DetectionCore

public final class HuggingFaceModelImporter: AIModelImporting, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func canHandle(_ reference: AIModelImportReference) -> Bool {
        if case .huggingFace = reference { return true }
        return false
    }

    public func importModel(
        reference: AIModelImportReference,
        into directory: URL,
        credentials: AIModelCredentials,
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> AIModelImportResult {
        guard case let .huggingFace(rawReference, displayName, revision, _) = reference else {
            throw AIModelCatalogError.invalidImportReference
        }
        guard let repositoryID = HuggingFaceRepository.parseRepositoryID(rawReference) else {
            throw AIModelCatalogError.invalidRepositoryReference
        }

        let resolvedName = displayName
            ?? RecommendedAIModelCatalog.model(for: repositoryID)?.title
            ?? repositoryID

        let downloader = HuggingFaceModelDownloader(session: session, accessToken: credentials.huggingFaceToken)

        // Inspect the file listing before downloading so a safetensors-only repo fails fast
        // instead of pulling hundreds of MB that we then reject as not runnable.
        let remoteInspection = try await downloader.inspectRemoteRepository(repositoryID: repositoryID, revision: revision)
        guard remoteInspection.isRunnable else {
            throw AIModelCatalogError.incompatibleModel(
                remoteInspection.reason ?? "This Hugging Face repo has no runnable ONNX or Core ML files."
            )
        }

        let totalBytes = try await downloader.download(
            repositoryID: repositoryID,
            revision: revision,
            into: directory
        ) { downloadProgress in
            progress(downloadProgress)
        }

        let validation = try AIModelBundleValidator.validate(directory: directory)
        try AIModelRunnableInspector.requireRunnable(validation)
        let model = InstalledAIModel(
            id: repositoryID,
            displayName: resolvedName,
            source: .huggingFace(repositoryID: repositoryID, revision: revision),
            format: validation.format,
            localDirectoryName: HuggingFaceRepository.directoryName(for: repositoryID),
            totalByteSize: totalBytes > 0 ? totalBytes : AIModelBundleValidator.directoryByteSize(at: directory)
        )
        return AIModelImportResult(model: model)
    }
}