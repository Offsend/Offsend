import Foundation
import DetectionCore

public protocol HuggingFaceModelDownloading: Sendable {
    func download(
        repositoryID: String,
        revision: String,
        into directory: URL,
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> Int64
}

public final class HuggingFaceModelDownloader: HuggingFaceModelDownloading, @unchecked Sendable {
    /// Only files the runtime actually reads: `config.json` (id2label) and `tokenizer.json`.
    /// Weights are matched by extension in `shouldDownload`; safetensors/PyTorch weights are
    /// never downloaded because no runtime here can execute them.
    private static let essentialRootFiles: Set<String> = [
        "config.json",
        "tokenizer.json",
    ]

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let accessToken: String?

    public init(session: URLSession = .shared, accessToken: String? = nil) {
        self.session = session
        self.accessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public func remoteFilePaths(repositoryID: String, revision: String) async throws -> [String] {
        try await listDownloadableFiles(repositoryID: repositoryID, revision: revision).map(\.path)
    }

    public func inspectRemoteRepository(repositoryID: String, revision: String) async throws -> AIModelRunnableInspection {
        let paths = try await remoteFilePaths(repositoryID: repositoryID, revision: revision)
        return AIModelRunnableInspector.inspectRemoteFilePaths(paths)
    }

    public func download(
        repositoryID: String,
        revision: String,
        into directory: URL,
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> Int64 {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let files = try await listDownloadableFiles(repositoryID: repositoryID, revision: revision)
        guard !files.isEmpty else {
            throw AIModelCatalogError.downloadFailed("No supported model files found in \(repositoryID).")
        }

        let totalBytes = files.reduce(Int64(0)) { $0 + $1.size }
        var downloadedBytes: Int64 = 0
        var completedFiles = 0

        for file in files {
            try Task.checkCancellation()
            guard let destination = AIModelFileStore.resolvedFileURL(
                forRelativePath: file.path,
                in: directory
            ) else {
                throw AIModelCatalogError.downloadFailed(
                    "Refusing to write outside the model directory: \(file.path)"
                )
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: destination.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path),
               let existingSize = attrs[.size] as? Int64,
               existingSize == file.size {
                downloadedBytes += file.size
                completedFiles += 1
                progress(
                    AIModelDownloadProgress(
                        modelID: repositoryID,
                        completedFiles: completedFiles,
                        totalFiles: files.count,
                        currentFileName: file.path,
                        downloadedBytes: downloadedBytes,
                        totalBytes: totalBytes
                    )
                )
                continue
            }

            guard let url = HuggingFaceRepository.resolveURL(
                repositoryID: repositoryID,
                revision: revision,
                relativePath: file.path
            ) else {
                throw AIModelCatalogError.downloadFailed("Invalid download URL for \(file.path).")
            }

            progress(
                AIModelDownloadProgress(
                    modelID: repositoryID,
                    completedFiles: completedFiles,
                    totalFiles: files.count,
                    currentFileName: file.path,
                    downloadedBytes: downloadedBytes,
                    totalBytes: totalBytes
                )
            )

            let request = authenticatedRequest(url: url)
            let (tempURL, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            try validate(response: response, repositoryID: repositoryID, filePath: file.path)

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            downloadedBytes += file.size
            completedFiles += 1
            progress(
                AIModelDownloadProgress(
                    modelID: repositoryID,
                    completedFiles: completedFiles,
                    totalFiles: files.count,
                    currentFileName: file.path,
                    downloadedBytes: downloadedBytes,
                    totalBytes: totalBytes
                )
            )
        }

        return downloadedBytes
    }

    private func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validate(response: URLResponse, repositoryID: String, filePath: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ... 299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw accessToken == nil ? AIModelCatalogError.unauthorized : AIModelCatalogError.downloadFailed(
                    "HTTP \(http.statusCode) while downloading \(filePath)."
                )
            }
            throw AIModelCatalogError.downloadFailed("HTTP \(http.statusCode) while downloading \(filePath).")
        }
    }

    private struct RemoteEntry: Decodable {
        let type: String
        let path: String
        let size: Int64?
    }

    private struct RemoteFile {
        let path: String
        let size: Int64
    }

    private func listDownloadableFiles(repositoryID: String, revision: String) async throws -> [RemoteFile] {
        guard let modelURL = HuggingFaceRepository.modelAPIURL(repositoryID: repositoryID) else {
            throw AIModelCatalogError.invalidRepositoryReference
        }

        let request = authenticatedRequest(url: modelURL)
        let (_, modelResponse) = try await session.data(for: request)
        if let http = modelResponse as? HTTPURLResponse {
            if http.statusCode == 404 {
                throw AIModelCatalogError.modelNotFound(repositoryID)
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw accessToken == nil ? AIModelCatalogError.unauthorized : AIModelCatalogError.downloadFailed(
                    "HTTP \(http.statusCode) while reading \(repositoryID)."
                )
            }
        }

        var collected: [RemoteFile] = []
        try await collectFiles(
            repositoryID: repositoryID,
            revision: revision,
            path: "",
            depth: 0,
            into: &collected
        )
        let retained = Self.retainedPaths(forAvailable: collected.map(\.path))
        return collected
            .filter { retained.contains($0.path) }
            .sorted { $0.path < $1.path }
    }

    /// Repos often ship several ONNX variants (fp32 + int8 + quantized) while the runtime loads
    /// exactly one (`preferredONNXPath`). Drop the unused variants *before* downloading — this
    /// saves hundreds of MB. External-weight files (`.onnx_data` / `.onnx.data`) are kept only
    /// when they belong to the preferred variant.
    static func retainedPaths(forAvailable paths: [String]) -> Set<String> {
        guard let preferred = AIModelBundleValidator.preferredONNXPath(in: paths) else {
            return Set(paths)
        }
        let preferredBase = String(preferred.dropLast(".onnx".count))
        return Set(paths.filter { path in
            if path.hasSuffix(".onnx") {
                return path == preferred
            }
            if path.hasSuffix(".onnx_data") || path.hasSuffix(".onnx.data") {
                return path.hasPrefix(preferredBase)
            }
            return true
        })
    }

    private func collectFiles(
        repositoryID: String,
        revision: String,
        path: String,
        depth: Int,
        into collected: inout [RemoteFile]
    ) async throws {
        guard depth <= 2 else { return }
        guard let url = HuggingFaceRepository.treeAPIURL(
            repositoryID: repositoryID,
            revision: revision,
            path: path
        ) else {
            throw AIModelCatalogError.invalidRepositoryReference
        }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 {
                throw AIModelCatalogError.modelNotFound(repositoryID)
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw accessToken == nil ? AIModelCatalogError.unauthorized : AIModelCatalogError.downloadFailed(
                    "HTTP \(http.statusCode) while listing \(repositoryID)."
                )
            }
            guard (200 ... 299).contains(http.statusCode) else {
                throw AIModelCatalogError.downloadFailed("Could not list files for \(repositoryID) (HTTP \(http.statusCode)).")
            }
        }

        let entries = try decoder.decode([RemoteEntry].self, from: data)
        for entry in entries {
            if entry.type == "directory" {
                let shouldDescend = depth == 0
                    ? entry.path == "onnx" || entry.path.hasSuffix("/onnx")
                    : entry.path.lowercased().contains("onnx")
                if shouldDescend {
                    try await collectFiles(
                        repositoryID: repositoryID,
                        revision: revision,
                        path: entry.path,
                        depth: depth + 1,
                        into: &collected
                    )
                }
                continue
            }

            guard entry.type == "file", shouldDownload(path: entry.path) else { continue }
            collected.append(RemoteFile(path: entry.path, size: entry.size ?? 0))
        }
    }

    private func shouldDownload(path: String) -> Bool {
        let fileName = (path as NSString).lastPathComponent
        if Self.essentialRootFiles.contains(fileName) {
            return true
        }
        // `.onnx_data` / `.onnx.data` hold external weights for large ONNX exports.
        if fileName.hasSuffix(".onnx") || fileName.hasSuffix(".onnx_data") || fileName.hasSuffix(".onnx.data") {
            return true
        }
        return false
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
