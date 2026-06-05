import Foundation

public protocol PDFRedactionDocumentExporting: Sendable {
    func export(session: PDFRedactionSession, to destinationURL: URL) throws -> PDFRedactionResult
}

public struct PDFRedactionDocumentExporter: PDFRedactionDocumentExporting {
    private let exporter: PDFRedactionExporting

    public init(exporter: PDFRedactionExporting = PDFRedactionExporter()) {
        self.exporter = exporter
    }

    public func export(session: PDFRedactionSession, to destinationURL: URL) throws -> PDFRedactionResult {
        try exporter.export(session: session, to: destinationURL)
    }
}
