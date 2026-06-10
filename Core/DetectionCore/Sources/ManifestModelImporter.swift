import Foundation

public final class ManifestModelImporter: AIModelImporting, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func canHandle(_ reference: AIModelImportReference) -> Bool {
        if case .manifest = reference { return true }
        return false
    }

    public func importModel(
        reference: AIModelImportReference,
        into directory: URL,
        credentials: AIModelCredentials,
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> AIModelImportResult {
        guard case let .manifest(manifestURL) = reference else {
            throw AIModelCatalogError.invalidImportReference
        }

        let manifestData: Data
        if manifestURL.isFileURL {
            manifestData = try Data(contentsOf: manifestURL)
        } else {
            guard manifestURL.scheme?.lowercased() == "https" else {
                throw AIModelCatalogError.importFailed("Manifest URL must use HTTPS.")
            }
            var request = URLRequest(url: manifestURL)
            for (key, value) in credentials.customHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                throw AIModelCatalogError.downloadFailed("HTTP \(http.statusCode) while fetching manifest.")
            }
            manifestData = data
        }

        let manifest = try AIModelManifestParser.parse(data: manifestData)
        let totalFiles = manifest.files.count
        var completed = 0
        var downloadedBytes: Int64 = 0

        progress(AIModelDownloadProgress(modelID: manifest.id, totalFiles: totalFiles))

        for file in manifest.files {
            try Task.checkCancellation()
            guard file.url.scheme?.lowercased() == "https" || file.url.isFileURL else {
                throw AIModelCatalogError.importFailed("Manifest file URLs must use HTTPS or file://.")
            }

            progress(
                AIModelDownloadProgress(
                    modelID: manifest.id,
                    completedFiles: completed,
                    totalFiles: totalFiles,
                    currentFileName: file.path
                )
            )

            let destination = directory.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if file.url.isFileURL {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: file.url, to: destination)
            } else {
                var request = URLRequest(url: file.url)
                for (key, value) in credentials.customHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }
                let (tempURL, response) = try await session.download(for: request)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                    throw AIModelCatalogError.downloadFailed("HTTP \(http.statusCode) while downloading \(file.path).")
                }
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
            }

            if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                downloadedBytes += Int64(size)
            }
            completed += 1
        }

        var checksumWarnings: [String] = []
        if let expected = manifest.sha256 {
            checksumWarnings = AIModelChecksumValidator.validate(directory: directory, expected: expected)
        }

        let validation = try AIModelBundleValidator.validate(directory: directory)
        try AIModelRunnableInspector.requireRunnable(validation)
        let byteSize = AIModelBundleValidator.directoryByteSize(at: directory)

        progress(
            AIModelDownloadProgress(
                modelID: manifest.id,
                completedFiles: completed,
                totalFiles: totalFiles,
                downloadedBytes: byteSize,
                totalBytes: byteSize
            )
        )

        let model = InstalledAIModel(
            id: manifest.id,
            displayName: manifest.displayName,
            source: .manifest(manifestURL: manifestURL),
            format: validation.format,
            localDirectoryName: manifest.id.replacingOccurrences(of: "/", with: "__"),
            totalByteSize: byteSize
        )
        return AIModelImportResult(model: model, checksumWarnings: checksumWarnings)
    }
}
