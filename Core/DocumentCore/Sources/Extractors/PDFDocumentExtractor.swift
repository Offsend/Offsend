#if canImport(PDFKit)
import Foundation
import PDFKit

public struct PDFDocumentExtractor: DocumentTextExtracting {
    public static let supportedExtensions: Set<String> = ["pdf"]

    public let id = "pdf"
    public let supportedFileExtensions: Set<String>

    public init(supportedFileExtensions: Set<String> = PDFDocumentExtractor.supportedExtensions) {
        self.supportedFileExtensions = supportedFileExtensions
    }

    public func canExtract(source: DocumentSource) -> Bool {
        supportedFileExtensions.contains(source.fileExtension)
    }

    public func extract(_ request: DocumentTextExtractionRequest) throws -> DocumentTextExtractionResult {
        guard let document = PDFDocument(data: request.data) else {
            throw DocumentProcessingError.invalidPDF
        }

        guard document.pageCount > 0 else {
            throw DocumentProcessingError.emptyDocument
        }

        var pageTexts: [String] = []
        pageTexts.reserveCapacity(document.pageCount)

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pageText.isEmpty else {
                continue
            }
            pageTexts.append(pageText)
        }

        let plainText = pageTexts.joined(separator: "\n\n")
        return DocumentTextExtractionResult(format: .pdf, plainText: plainText, pdfData: request.data)
    }
}
#endif
