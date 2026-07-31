import DetectionCore
import PDFKit
import RiskScoringCore
import XCTest
@testable import DocumentCore

final class PDFRedactionEngineTests: XCTestCase {
    private let engine = PDFRedactionEngine()
    private let planBuilder = PDFRedactionPlanBuilder()

    func testPreviewApplyReturnsPDFData() throws {
        let pdfData = PDFTestFixtures.makePDF(containing: "Secret value")
        let plan = PDFRedactionPlan(regions: [
            PDFRedactionRegion(
                pageIndex: 0,
                bounds: CGRect(x: 72, y: 672, width: 120, height: 14),
                source: .manual
            )
        ])

        let previewData = try engine.apply(plan: plan, to: pdfData, mode: .preview)

        XCTAssertFalse(previewData.isEmpty)
        XCTAssertNotEqual(previewData, pdfData)
    }

    func testApplyRejectsEmptyPlan() throws {
        let pdfData = PDFTestFixtures.makePDF(containing: "Secret value")
        let plan = PDFRedactionPlan(regions: [])

        XCTAssertThrowsError(try engine.apply(plan: plan, to: pdfData, mode: .preview)) { error in
            XCTAssertEqual(error as? PDFRedactionError, .emptyPlan)
        }
    }

    func testPermanentApplyRemovesExtractableSensitiveText() throws {
        let secret = "ivan@acme.com"
        let plainText = "Send invoice to \(secret)"
        let entity = RedactionFixtures.entity(type: .email, value: secret, in: plainText)
        let pdfData = PDFTestFixtures.makePDF(containing: plainText)
        let plan = try planBuilder.buildPlan(
            analysis: RedactionFixtures.analysis(plainText: plainText, entities: [entity]),
            pdfData: pdfData,
            selectedEntityIDs: Set([entity.id]),
            manualRegions: []
        )

        XCTAssertTrue(plan.unresolvedValues.isEmpty, "Fixture should resolve email in PDF text layer")

        let redactedData = try engine.apply(plan: plan, to: pdfData, mode: .permanent)
        let extracted = Self.extractPlainText(from: redactedData)

        XCTAssertFalse(extracted.localizedCaseInsensitiveContains(secret))
    }

    func testPermanentApplyStillAllowsPreviewStyleRegionsOnOtherPages() throws {
        let secret = "client@example.com"
        let pdfData = PDFTestFixtures.makePDF(pages: [
            "Page one \(secret)",
            "Page two clean"
        ])
        let entity = RedactionFixtures.entity(type: .email, value: secret, in: "Page one \(secret)")
        let plan = try planBuilder.buildPlan(
            analysis: RedactionFixtures.analysis(plainText: "Page one \(secret)\n\nPage two clean", entities: [entity]),
            pdfData: pdfData,
            selectedEntityIDs: Set([entity.id]),
            manualRegions: []
        )

        let redactedData = try engine.apply(plan: plan, to: pdfData, mode: .permanent)

        XCTAssertEqual(PDFDocument(data: redactedData)?.pageCount, 2)
        let extracted = Self.extractPlainText(from: redactedData)
        XCTAssertFalse(extracted.localizedCaseInsensitiveContains(secret))
        // Page two has no redactions, so its text layer must stay searchable (vector preserved).
        XCTAssertTrue(extracted.contains("Page two clean"))
    }

    private static func extractPlainText(from pdfData: Data) -> String {
        guard let document = PDFDocument(data: pdfData) else { return "" }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

}
