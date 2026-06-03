import AppKit
import CoreText
import Foundation

enum PDFTestFixtures {
    static func makePDF(containing text: String) -> Data {
        makePDF(pages: [text])
    }

    static func makePDF(pages: [String]) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            preconditionFailure("Unable to create PDF context")
        }

        for text in pages {
            context.beginPDFPage(nil)
            draw(text: text, in: context, pageHeight: pageHeight, pageWidth: pageWidth)
            context.endPDFPage()
        }

        context.closePDF()

        return pdfData as Data
    }

    static func makeEmptyPDF() -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            preconditionFailure("Unable to create PDF context")
        }

        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    private static func draw(text: String, in context: CGContext, pageHeight: CGFloat, pageWidth: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(x: 72, y: pageHeight - 120, width: pageWidth - 144, height: 72),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
    }
}
