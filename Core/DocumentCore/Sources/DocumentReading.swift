import Foundation

public protocol DocumentReading: Sendable {
    func data(at url: URL) throws -> Data
}

public struct FileManagerDocumentReader: DocumentReading {
    public init() {}

    public func data(at url: URL) throws -> Data {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw DocumentProcessingError.unreadableFile(message: "File does not exist.")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw DocumentProcessingError.unreadableFile(message: error.localizedDescription)
        }
    }
}
