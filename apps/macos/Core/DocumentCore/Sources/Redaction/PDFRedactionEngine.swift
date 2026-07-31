#if canImport(AppKit) && canImport(PDFKit)
import AppKit
import Foundation
import PDFKit

public struct PDFRedactionEngine: PDFRedactionApplying {
    private static let rasterizationScale: CGFloat = 2

    public init() {}

    public func apply(
        plan: PDFRedactionPlan,
        to pdfData: Data,
        mode: PDFRedactionApplyMode
    ) throws -> Data {
        guard let document = PDFDocument(data: pdfData)?.copy() as? PDFDocument else {
            throw PDFRedactionError.invalidPDF
        }

        guard !document.isLocked else {
            throw PDFRedactionError.encryptedPDF
        }

        guard !plan.regions.isEmpty else {
            throw PDFRedactionError.emptyPlan
        }

        switch mode {
        case .preview:
            for region in plan.regions {
                guard let page = document.page(at: region.pageIndex) else { continue }
                page.addAnnotation(makePreviewAnnotation(for: region))
            }
            return document.dataRepresentation() ?? pdfData
        case .permanent:
            return try burnRedactions(plan: plan, in: document)
        }
    }

    private func makePreviewAnnotation(for region: PDFRedactionRegion) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: region.bounds, forType: .square, withProperties: nil)
        annotation.color = NSColor.black
        annotation.interiorColor = NSColor.black
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = 0
        annotation.shouldDisplay = true
        annotation.shouldPrint = true
        return annotation
    }

    private func burnRedactions(plan: PDFRedactionPlan, in sourceDocument: PDFDocument) throws -> Data {
        for region in plan.regions {
            guard region.pageIndex >= 0,
                  region.pageIndex < sourceDocument.pageCount,
                  sourceDocument.page(at: region.pageIndex) != nil else {
                throw PDFRedactionError.exportFailed(
                    message: "Redaction region references invalid page index \(region.pageIndex)."
                )
            }
        }

        // Rasterize only pages that actually carry redactions; untouched pages keep their
        // original vector content (smaller output, preserved quality, links and outline).
        let regionsByPage = Dictionary(grouping: plan.regions, by: \.pageIndex)

        for (pageIndex, regions) in regionsByPage {
            guard let page = sourceDocument.page(at: pageIndex) else { continue }
            let burnedPage = try renderBurnedPage(page, regions: regions)
            sourceDocument.removePage(at: pageIndex)
            sourceDocument.insert(burnedPage, at: pageIndex)
        }

        guard let data = sourceDocument.dataRepresentation() else {
            throw PDFRedactionError.exportFailed(message: "Unable to serialize redacted PDF.")
        }
        return data
    }

    private func renderBurnedPage(_ page: PDFPage, regions: [PDFRedactionRegion]) throws -> PDFPage {
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else {
            throw PDFRedactionError.exportFailed(message: "PDF page has invalid dimensions.")
        }

        let scale = Self.rasterizationScale
        let pixelWidth = Int(ceil(mediaBox.width * scale))
        let pixelHeight = Int(ceil(mediaBox.height * scale))
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw PDFRedactionError.exportFailed(message: "PDF page has invalid raster dimensions.")
        }

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PDFRedactionError.exportFailed(message: "Unable to create rasterization context.")
        }

        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)

        page.draw(with: .mediaBox, to: context)

        context.setFillColor(CGColor.black)
        for region in regions {
            context.fill(region.bounds)
        }
        context.restoreGState()

        guard let cgImage = context.makeImage() else {
            throw PDFRedactionError.exportFailed(message: "Unable to rasterize redacted page.")
        }

        return try makePDFPage(from: cgImage, mediaBox: mediaBox)
    }

    private func makePDFPage(from cgImage: CGImage, mediaBox: CGRect) throws -> PDFPage {
        let pageData = NSMutableData()
        var mediaBox = mediaBox

        guard let consumer = CGDataConsumer(data: pageData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFRedactionError.exportFailed(message: "Unable to create redacted PDF page.")
        }

        pdfContext.beginPDFPage(nil)
        pdfContext.draw(cgImage, in: mediaBox)
        pdfContext.endPDFPage()
        pdfContext.closePDF()

        guard let document = PDFDocument(data: pageData as Data),
              let page = document.page(at: 0) else {
            throw PDFRedactionError.exportFailed(message: "Unable to load redacted PDF page.")
        }

        return page
    }
}
#endif
