import Foundation

public struct PlainTextDocumentExtractor: DocumentTextExtracting {
    public static let supportedExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "json", "log", "xml", "yaml", "yml", "rtf"
    ]

    public let id = "plain-text"
    public let supportedFileExtensions: Set<String>

    public init(supportedFileExtensions: Set<String> = PlainTextDocumentExtractor.supportedExtensions) {
        self.supportedFileExtensions = supportedFileExtensions
    }

    public func canExtract(source: DocumentSource) -> Bool {
        supportedFileExtensions.contains(source.fileExtension)
    }

    public func extract(_ request: DocumentTextExtractionRequest) throws -> DocumentTextExtractionResult {
        let text = Self.decodeText(from: request.data)
        return DocumentTextExtractionResult(format: .plainText, plainText: text)
    }

    private static func decodeText(from data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        return String(decoding: data, as: UTF8.self)
    }
}
