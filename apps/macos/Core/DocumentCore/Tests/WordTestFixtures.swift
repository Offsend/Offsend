import AppKit
import PDFKit

enum WordTestFixtures {
    static func makeDocx(containing text: String) throws -> Data {
        try makeWordData(containing: text, documentType: .officeOpenXML)
    }

    static func makeDoc(containing text: String) throws -> Data {
        try makeWordData(containing: text, documentType: .docFormat)
    }

    static func extractPlainText(from pdfData: Data) -> String {
        guard let document = PDFDocument(data: pdfData) else { return "" }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    private static func makeWordData(
        containing text: String,
        documentType: NSAttributedString.DocumentType
    ) throws -> Data {
        let attributed = NSAttributedString(string: text)
        return try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: documentType]
        )
    }
}
