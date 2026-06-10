import Foundation

public enum DocumentPrepareSelection: Equatable, Sendable {
    case directory(URL)
    case documents([URL])

    public var url: URL {
        switch self {
        case let .directory(url):
            return url
        case let .documents(urls):
            return urls[0]
        }
    }
}

public enum DocumentPrepareSelectionClassifier {
    public static func selection(for url: URL) -> DocumentPrepareSelection? {
        selection(forMultiple: [url])
    }

    public static func selection(forMultiple urls: [URL]) -> DocumentPrepareSelection? {
        let standardizedURLs = urls.map(\.standardizedFileURL)

        if let directory = standardizedURLs.first(where: { isDirectory($0) }) {
            return .directory(directory)
        }

        var seenPaths = Set<String>()
        let supportedFiles = standardizedURLs.filter { url in
            guard isSupportedFile(url) else { return false }
            let path = url.path
            guard seenPaths.insert(path).inserted else { return false }
            return true
        }

        guard !supportedFiles.isEmpty else { return nil }
        return .documents(supportedFiles)
    }

    public static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public static func isSupportedFile(_ url: URL) -> Bool {
        DocumentTextExtractorRegistry.canProcessFile(at: url)
    }
}
