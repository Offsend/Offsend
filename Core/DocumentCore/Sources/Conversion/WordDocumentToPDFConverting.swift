import AppKit
import CoreText
import Foundation

public protocol WordDocumentToPDFConverting: Sendable {
    func convert(data: Data, fileExtension: String) throws -> Data
}

public struct AppKitWordDocumentToPDFConverter: WordDocumentToPDFConverting {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 72

    public init() {}

    public func convert(data: Data, fileExtension: String) throws -> Data {
        let documentType = try Self.documentType(for: fileExtension)

        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        ) else {
            throw DocumentProcessingError.extractionFailed(message: "Unable to read Word document.")
        }

        guard attributed.length > 0 else {
            throw DocumentProcessingError.emptyDocument
        }

        return try Self.renderPDF(from: attributed)
    }

    private static func documentType(for fileExtension: String) throws -> NSAttributedString.DocumentType {
        switch fileExtension.lowercased() {
        case "docx":
            return .officeOpenXML
        case "doc":
            return .docFormat
        default:
            throw DocumentProcessingError.unsupportedFormat(fileExtension: fileExtension)
        }
    }

    private static func renderPDF(from attributedString: NSAttributedString) throws -> Data {
        let textWidth = pageWidth - 2 * margin
        let textHeight = pageHeight - 2 * margin
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw DocumentProcessingError.extractionFailed(message: "Unable to create PDF.")
        }

        var currentIndex = 0
        let totalLength = attributedString.length

        while currentIndex < totalLength {
            context.beginPDFPage(nil)

            let path = CGPath(
                rect: CGRect(x: margin, y: margin, width: textWidth, height: textHeight),
                transform: nil
            )
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: currentIndex, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            guard visibleRange.length > 0 else { break }

            currentIndex += visibleRange.length
            context.endPDFPage()
        }

        context.closePDF()
        return pdfData as Data
    }
}
