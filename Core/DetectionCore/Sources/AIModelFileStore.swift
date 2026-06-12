import Foundation

public enum AIModelFileStore {
    public static func baseDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Offsend", isDirectory: true)
    }

    public static func modelsDirectory() -> URL {
        baseDirectory().appendingPathComponent("Models", isDirectory: true)
    }

    public static func modelDirectory(for localDirectoryName: String) -> URL {
        modelsDirectory().appendingPathComponent(localDirectoryName, isDirectory: true)
    }

    public static func ensureModelsDirectory() throws {
        try FileManager.default.createDirectory(at: modelsDirectory(), withIntermediateDirectories: true)
    }

    public static func deleteModelFiles(localDirectoryName: String) throws {
        let directory = modelDirectory(for: localDirectoryName)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// Legacy helper for Hugging Face repository ids.
    public static func modelDirectory(forRepositoryID repositoryID: String) -> URL {
        modelDirectory(for: HuggingFaceRepository.directoryName(for: repositoryID))
    }

    public static func deleteModelFiles(repositoryID: String) throws {
        try deleteModelFiles(localDirectoryName: HuggingFaceRepository.directoryName(for: repositoryID))
    }

    public static func copyContents(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            throw AIModelCatalogError.importFailed("Could not read source folder.")
        }

        let sourcePrefix = source.path.hasSuffix("/") ? source.path : source.path + "/"
        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: Set(resourceKeys))
            let relativePath: String
            if itemURL.path.hasPrefix(sourcePrefix) {
                relativePath = String(itemURL.path.dropFirst(sourcePrefix.count))
            } else {
                relativePath = itemURL.lastPathComponent
            }
            let targetURL = destination.appendingPathComponent(relativePath)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.copyItem(at: itemURL, to: targetURL)
            }
        }
    }
}
