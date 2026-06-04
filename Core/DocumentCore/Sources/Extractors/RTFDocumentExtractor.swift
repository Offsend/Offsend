import AppKit
import Foundation

public struct RTFDocumentExtractor: DocumentTextExtracting {
    public static let supportedExtensions: Set<String> = ["rtf"]

    public let id = "rtf"
    public let supportedFileExtensions: Set<String>

    public init(supportedFileExtensions: Set<String> = RTFDocumentExtractor.supportedExtensions) {
        self.supportedFileExtensions = supportedFileExtensions
    }

    public func canExtract(source: DocumentSource) -> Bool {
        supportedFileExtensions.contains(source.fileExtension)
    }

    public func extract(_ request: DocumentTextExtractionRequest) throws -> DocumentTextExtractionResult {
        guard let attributed = try? NSAttributedString(
            data: request.data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            throw DocumentProcessingError.extractionFailed(message: "Unable to read RTF document.")
        }
        return DocumentTextExtractionResult(format: .plainText, plainText: attributed.string)
    }
}
