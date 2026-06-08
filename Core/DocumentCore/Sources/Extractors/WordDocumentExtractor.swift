import Foundation

public struct WordDocumentExtractor: DocumentTextExtracting {
    public static let supportedExtensions: Set<String> = ["doc", "docx"]

    public let id = "word"
    public let supportedFileExtensions: Set<String>
    private let converter: WordDocumentToPDFConverting
    private let pdfExtractor: PDFDocumentExtractor

    public init(
        supportedFileExtensions: Set<String> = WordDocumentExtractor.supportedExtensions,
        converter: WordDocumentToPDFConverting = AppKitWordDocumentToPDFConverter(),
        pdfExtractor: PDFDocumentExtractor = PDFDocumentExtractor()
    ) {
        self.supportedFileExtensions = supportedFileExtensions
        self.converter = converter
        self.pdfExtractor = pdfExtractor
    }

    public func canExtract(source: DocumentSource) -> Bool {
        supportedFileExtensions.contains(source.fileExtension)
    }

    public func extract(_ request: DocumentTextExtractionRequest) throws -> DocumentTextExtractionResult {
        let pdfData = try converter.convert(
            data: request.data,
            fileExtension: request.source.fileExtension
        )

        let pdfRequest = DocumentTextExtractionRequest(
            data: pdfData,
            source: request.source,
            maximumExtractedCharacterCount: request.maximumExtractedCharacterCount
        )
        let pdfResult = try pdfExtractor.extract(pdfRequest)

        return DocumentTextExtractionResult(
            format: .pdf,
            plainText: pdfResult.plainText,
            warnings: pdfResult.warnings,
            pdfData: pdfData
        )
    }
}
