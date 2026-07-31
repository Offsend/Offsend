import AppKit
import DocumentCore
import Foundation

typealias PrepareSelection = DocumentPrepareSelection

enum PrepareURLClassification {
    static func selection(for url: URL) -> PrepareSelection? {
        DocumentPrepareSelectionClassifier.selection(for: url)
    }

    static func selection(forMultiple urls: [URL]) -> PrepareSelection? {
        DocumentPrepareSelectionClassifier.selection(forMultiple: urls)
    }

    static func selection(forWindowPath path: String) -> PrepareSelection? {
        selection(for: URL(fileURLWithPath: path))
    }

    static func isDirectory(_ url: URL) -> Bool {
        DocumentPrepareSelectionClassifier.isDirectory(url)
    }

    static func isSupportedFile(_ url: URL) -> Bool {
        DocumentPrepareSelectionClassifier.isSupportedFile(url)
    }

    static func selectionFromPasteboard() -> PrepareSelection? {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] {
            return selection(forMultiple: urls.map { $0 as URL })
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
