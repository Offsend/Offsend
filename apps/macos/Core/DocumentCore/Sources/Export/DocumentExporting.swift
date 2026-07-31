import Foundation

public enum DocumentExportFormat: Sendable, Equatable {
    case plainText
    case pdfRedaction
}

public protocol DocumentExporting: Sendable {
    func export(
        _ sanitization: DocumentSanitizationResult,
        format: DocumentExportFormat,
        session: PDFRedactionSession?,
        to destinationURL: URL
    ) throws
}

public struct DocumentExporter: DocumentExporting {
    private let plainTextExporter: PlainTextDocumentExporting
    private let pdfRedactionExporter: PDFRedactionDocumentExporting

    public init(
        plainTextExporter: PlainTextDocumentExporting = PlainTextDocumentExporter(),
        pdfRedactionExporter: PDFRedactionDocumentExporting = PDFRedactionDocumentExporter()
    ) {
        self.plainTextExporter = plainTextExporter
        self.pdfRedactionExporter = pdfRedactionExporter
    }

    public func export(
        _ sanitization: DocumentSanitizationResult,
        format: DocumentExportFormat,
        session: PDFRedactionSession?,
        to destinationURL: URL
    ) throws {
        switch format {
        case .plainText:
            try plainTextExporter.export(sanitization, to: destinationURL)
        case .pdfRedaction:
            guard let session else {
                throw PDFRedactionError.unsupportedFormat
            }
            _ = try pdfRedactionExporter.export(session: session, to: destinationURL)
        }
    }
}
