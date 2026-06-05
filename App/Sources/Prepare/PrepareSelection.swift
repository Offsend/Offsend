import AppKit
import DocumentCore
import Foundation

enum PrepareSelection: Equatable {
    case directory(URL)
    case document(URL)

    var url: URL {
        switch self {
        case let .directory(url), let .document(url):
            return url
        }
    }
}

enum PrepareURLClassification {
    static func selection(for url: URL) -> PrepareSelection? {
        let standardized = url.standardizedFileURL
        if isDirectory(standardized) {
            return .directory(standardized)
        }
        if isSupportedFile(standardized) {
            return .document(standardized)
        }
        return nil
    }

    static func selection(forWindowPath path: String) -> PrepareSelection? {
        selection(for: URL(fileURLWithPath: path))
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static func isSupportedFile(_ url: URL) -> Bool {
        guard !isDirectory(url) else { return false }
        return DocumentTextExtractorRegistry.supportedFileExtensions.contains(
            url.pathExtension.lowercased()
        )
    }

    static func selectionFromPasteboard() -> PrepareSelection? {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] {
            let fileURLs = urls.map { $0 as URL }
            if let directory = fileURLs.first(where: { isDirectory($0) }) {
                return .directory(directory)
            }
            if let file = fileURLs.first(where: { isSupportedFile($0) }) {
                return .document(file)
            }
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURLString),
           url.isFileURL,
           let selection = selection(for: url) {
            return selection
        }

        return nil
    }
}
