import Foundation
import DetectionCore

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
            guard let targetURL = resolvedFileURL(forRelativePath: relativePath, in: destination) else {
                throw AIModelCatalogError.importFailed("Refusing to write outside the model directory: \(relativePath)")
            }
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

    /// Resolves `relativePath` under `directory` and returns nil if it would escape
    /// (absolute paths, `..` segments, or symlink-assisted breakouts).
    public static func resolvedFileURL(forRelativePath relativePath: String, in directory: URL) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") { return nil }
        if trimmed.contains("\0") { return nil }

        let components = (trimmed as NSString).pathComponents
        if components.contains("..") || components.contains("~") { return nil }

        let root = directory.standardizedFileURL
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        let rootPath = root.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            return nil
        }

        let resolvedRootPath = root.resolvingSymlinksInPath().path
        let resolvedAncestorPath = nearestExistingAncestor(of: candidate).resolvingSymlinksInPath().path
        guard resolvedAncestorPath == resolvedRootPath
            || resolvedAncestorPath.hasPrefix(resolvedRootPath + "/")
        else {
            return nil
        }
        return candidate
    }

    private static func nearestExistingAncestor(of url: URL) -> URL {
        var current = url.standardizedFileURL
        let fileManager = FileManager.default
        while !fileManager.fileExists(atPath: current.path) {
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
        return current
    }
}
