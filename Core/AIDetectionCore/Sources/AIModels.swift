import Foundation

// MARK: - Source & format

public enum AIModelSource: Codable, Equatable, Sendable {
    case huggingFace(repositoryID: String, revision: String)
    case importedFolder(originalPath: String)
    case remoteURL(baseURL: URL)
    case manifest(manifestURL: URL)
    case ollama(endpoint: URL, modelName: String)
}

public enum AIModelFormat: String, Codable, Sendable, CaseIterable {
    case huggingFaceTransformers
    case onnxTokenClassification
    case coreML
    case gguf
    case ollamaAPI
}

public struct InstalledAIModel: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public let source: AIModelSource
    public let format: AIModelFormat
    public var localDirectoryName: String
    public var downloadedAt: Date
    public var totalByteSize: Int64

    public init(
        id: String,
        displayName: String,
        source: AIModelSource,
        format: AIModelFormat,
        localDirectoryName: String,
        downloadedAt: Date = Date(),
        totalByteSize: Int64 = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.format = format
        self.localDirectoryName = localDirectoryName
        self.downloadedAt = downloadedAt
        self.totalByteSize = totalByteSize
    }

    public var isVerified: Bool {
        guard case .huggingFace(let repositoryID, _) = source else { return false }
        return RecommendedAIModelCatalog.model(for: repositoryID) != nil
    }

    public var huggingFaceRepositoryID: String? {
        guard case .huggingFace(let repositoryID, _) = source else { return nil }
        return repositoryID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case source
        case format
        case localDirectoryName
        case downloadedAt
        case totalByteSize
        case repositoryID
        case revision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(String.self, forKey: .id),
           let source = try container.decodeIfPresent(AIModelSource.self, forKey: .source),
           let format = try container.decodeIfPresent(AIModelFormat.self, forKey: .format),
           let localDirectoryName = try container.decodeIfPresent(String.self, forKey: .localDirectoryName) {
            self.id = id
            self.displayName = try container.decode(String.self, forKey: .displayName)
            self.source = source
            self.format = format
            self.localDirectoryName = localDirectoryName
            self.downloadedAt = try container.decodeIfPresent(Date.self, forKey: .downloadedAt) ?? Date()
            self.totalByteSize = try container.decodeIfPresent(Int64.self, forKey: .totalByteSize) ?? 0
            return
        }

        let repositoryID = try container.decode(String.self, forKey: .repositoryID)
        let revision = try container.decodeIfPresent(String.self, forKey: .revision) ?? "main"
        self.id = repositoryID
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.source = .huggingFace(repositoryID: repositoryID, revision: revision)
        self.format = .onnxTokenClassification
        self.localDirectoryName = HuggingFaceRepository.directoryName(for: repositoryID)
        self.downloadedAt = try container.decodeIfPresent(Date.self, forKey: .downloadedAt) ?? Date()
        self.totalByteSize = try container.decodeIfPresent(Int64.self, forKey: .totalByteSize) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(source, forKey: .source)
        try container.encode(format, forKey: .format)
        try container.encode(localDirectoryName, forKey: .localDirectoryName)
        try container.encode(downloadedAt, forKey: .downloadedAt)
        try container.encode(totalByteSize, forKey: .totalByteSize)
    }
}

// MARK: - Import

public enum AIModelImportReference: Equatable, Sendable {
    case huggingFace(rawReference: String, displayName: String?, revision: String, requiresToken: Bool)
    case folder(URL)
    case remoteURL(URL)
    case manifest(URL)
    case ollama(endpoint: String, modelName: String)
    case ggufFile(URL)
}

public struct AIModelCredentials: Sendable {
    public var huggingFaceToken: String?
    public var customHeaders: [String: String]

    public init(huggingFaceToken: String? = nil, customHeaders: [String: String] = [:]) {
        self.huggingFaceToken = huggingFaceToken
        self.customHeaders = customHeaders
    }
}

public struct AIModelImportResult: Equatable, Sendable {
    public let model: InstalledAIModel
    public let checksumWarnings: [String]

    public init(model: InstalledAIModel, checksumWarnings: [String] = []) {
        self.model = model
        self.checksumWarnings = checksumWarnings
    }
}

public protocol AIModelImporting: Sendable {
    func canHandle(_ reference: AIModelImportReference) -> Bool
    func importModel(
        reference: AIModelImportReference,
        into directory: URL,
        credentials: AIModelCredentials,
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> AIModelImportResult
}

// MARK: - Progress & errors

public struct AIModelDownloadProgress: Equatable, Sendable {
    public var modelID: String
    public var completedFiles: Int
    public var totalFiles: Int
    public var currentFileName: String
    public var downloadedBytes: Int64
    public var totalBytes: Int64

    public init(
        modelID: String,
        completedFiles: Int = 0,
        totalFiles: Int = 0,
        currentFileName: String = "",
        downloadedBytes: Int64 = 0,
        totalBytes: Int64 = 0
    ) {
        self.modelID = modelID
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.currentFileName = currentFileName
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
    }

    public var fractionCompleted: Double {
        guard totalBytes > 0 else {
            guard totalFiles > 0 else { return 0 }
            return Double(completedFiles) / Double(totalFiles)
        }
        return Double(downloadedBytes) / Double(totalBytes)
    }
}

public enum AIModelCatalogError: Error, Equatable, Sendable {
    case invalidRepositoryReference
    case invalidImportReference
    case modelNotFound(String)
    case downloadFailed(String)
    case importFailed(String)
    case catalogSaveFailed(String)
    case gatedModelRequiresToken
    case unauthorized
    case unsupportedFormat(String)
    case checksumMismatch(String)
    case incompatibleModel(String)
}

extension AIModelCatalogError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRepositoryReference:
            return "Enter a Hugging Face model id (author/name) or a huggingface.co URL."
        case .invalidImportReference:
            return "Invalid model import reference."
        case .modelNotFound(let id):
            return "Model not found: \(id)."
        case .downloadFailed(let message), .importFailed(let message):
            return message
        case .catalogSaveFailed(let message):
            return "Could not save the model catalog: \(message)"
        case .gatedModelRequiresToken:
            return "Add your Hugging Face access token in Settings → AI."
        case .unauthorized:
            return "Authentication failed. Add a Hugging Face access token for gated models."
        case .unsupportedFormat(let message):
            return message
        case .checksumMismatch(let message):
            return message
        case .incompatibleModel(let message):
            return message
        }
    }
}
