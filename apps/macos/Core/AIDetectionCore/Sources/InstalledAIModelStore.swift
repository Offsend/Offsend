import Foundation

public protocol InstalledAIModelStoring: Sendable {
    func loadInstalledAIModels() throws -> [InstalledAIModel]
    func saveInstalledAIModels(_ models: [InstalledAIModel]) throws
}

public final class InstalledAIModelStore: InstalledAIModelStoring, Sendable {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL? = nil) throws {
        self.directory = directory ?? Self.defaultDirectory()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func loadInstalledAIModels() throws -> [InstalledAIModel] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([InstalledAIModel].self, from: Data(contentsOf: url))
    }

    public func saveInstalledAIModels(_ models: [InstalledAIModel]) throws {
        let data = try encoder.encode(models)
        try data.write(to: fileURL, options: [.atomic])
    }

    private var fileURL: URL {
        directory.appendingPathComponent("ai_models.json")
    }

    private static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Offsend", isDirectory: true)
    }
}

public final class InMemoryInstalledAIModelStore: InstalledAIModelStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var models: [InstalledAIModel]

    public init(models: [InstalledAIModel] = []) {
        self.models = models
    }

    public func loadInstalledAIModels() throws -> [InstalledAIModel] {
        lock.withLock { models }
    }

    public func saveInstalledAIModels(_ models: [InstalledAIModel]) throws {
        lock.withLock {
            self.models = models
        }
    }
}
