#if canImport(PDFKit)
import CoreGraphics
import DetectionCore
import Foundation
import PDFKit

public struct PDFRedactionRegionResolver: PDFRedactionRegionResolving {
    public init() {}

    public func resolveRegions(
        in pdfData: Data,
        entities: [SensitiveEntity],
        padding: CGFloat = PDFRedactionDefaults.regionPadding
    ) throws -> [PDFRedactionRegion] {
        guard let document = PDFDocument(data: pdfData) else {
            throw PDFRedactionError.invalidPDF
        }

        guard document.pageCount > 0 else {
            throw PDFRedactionError.noTextLayer
        }

        if document.isEncrypted, document.isLocked {
            throw PDFRedactionError.encryptedPDF
        }

        let uniqueValues = entities.uniqueByValue()
        guard !uniqueValues.isEmpty else { return [] }

        // One pass over pages; `page.string` is expensive, so resolve every value per page.
        var regions: [PDFRedactionRegion] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string else {
                continue
            }

            for (entityID, value) in uniqueValues {
                var searchRange = pageText.startIndex..<pageText.endIndex
                while let range = pageText.range(
                    of: value,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                ) {
                    let nsRange = NSRange(range, in: pageText)
                    guard let selection = page.selection(for: nsRange) else {
                        searchRange = range.upperBound..<pageText.endIndex
                        continue
                    }

                    regions.append(
                        PDFRedactionRegion(
                            pageIndex: pageIndex,
                            bounds: selection.bounds(for: page).insetBy(dx: -padding, dy: -padding),
                            source: .detected(entityID: entityID, value: value)
                        )
                    )
                    searchRange = range.upperBound..<pageText.endIndex
                }
            }
        }

        return regions
    }
}
#endif
