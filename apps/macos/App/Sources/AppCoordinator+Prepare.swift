import Foundation

extension AppCoordinator {
    func openPrepare(for url: URL, source: String) {
        let standardized = url.standardizedFileURL
        if PrepareURLClassification.isDirectory(standardized) {
            recordDirectoryCheckOpened(source: source)
        } else if PrepareURLClassification.isSupportedFile(standardized) {
            recordDocumentSanitizeOpened(source: source)
        }
        openPrepareWindowAction?(standardized)
    }

    func openPrepareWindow(source: String) {
        openPrepareWindowAction?(nil)
    }
}
