import Foundation
import DetectionCore

public final class URLModelImporter: AIModelImporting, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func canHandle(_ reference: AIModelImportReference) -> Bool {
        if case .remoteURL = reference { return true }
        return false
    }

    public func importModel(
        reference: AIModelImportReference,
        into directory: URL,
        credentials: AIModelCredentials,
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> AIModelImportResult {
        guard case let .remoteURL(url) = reference else {
            throw AIModelCatalogError.invalidImportReference
        }
        guard url.scheme?.lowercased() == "https" else {
            throw AIModelCatalogError.importFailed("Only HTTPS URLs are supported.")
        }

        let modelID = UUID().uuidString
        progress(AIModelDownloadProgress(modelID: modelID, currentFileName: url.lastPathComponent))

        var request = URLRequest(url: url)
        for (key, value) in credentials.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (tempURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw AIModelCatalogError.downloadFailed("HTTP \(http.statusCode) while downloading model.")
        }

        let fileName = url.lastPathComponent
        let lowercased = fileName.lowercased()
        if lowercased.hasSuffix(".zip") {
            try extractZip(from: tempURL, into: directory)
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(fileName.isEmpty ? "model.onnx" : fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: tempURL, to: destination)
        }

        let validation = try AIModelBundleValidator.validate(directory: directory)
        try AIModelRunnableInspector.requireRunnable(validation)
        let byteSize = AIModelBundleValidator.directoryByteSize(at: directory)
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
            displayName: url.lastPathComponent.isEmpty ? "Remote model" : url.deletingPathExtension().lastPathComponent,
            source: .remoteURL(baseURL: url),
            format: validation.format,
            localDirectoryName: modelID,
            totalByteSize: byteSize
        )
        return AIModelImportResult(model: model)
    }

    private func extractZip(from archiveURL: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", archiveURL.path, "-d", directory.path]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AIModelCatalogError.importFailed("Could not extract ZIP archive.")
        }
    }
}
