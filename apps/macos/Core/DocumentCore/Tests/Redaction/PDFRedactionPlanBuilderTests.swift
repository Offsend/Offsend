import DetectionCore
import RiskScoringCore
import XCTest
@testable import DocumentCore

final class PDFRedactionPlanBuilderTests: XCTestCase {
    private let builder = PDFRedactionPlanBuilder()

    func testBuildPlanIncludesManualRegionsForPDF() throws {
        let email = "client@example.com"
        let pdfData = PDFTestFixtures.makePDF(containing: "Invoice for \(email)")
        let analysis = RedactionFixtures.analysis(plainText: "Invoice for \(email)", entities: [
            RedactionFixtures.entity(type: .email, value: email, in: "Invoice for \(email)")
        ])

        let manualRegion = PDFRedactionRegion(
            pageIndex: 0,
            bounds: CGRect(x: 10, y: 10, width: 40, height: 12),
            source: .manual
        )

        let plan = try builder.buildPlan(
            analysis: analysis,
            pdfData: pdfData,
            selectedEntityIDs: [],
            manualRegions: [manualRegion]
        )

        XCTAssertEqual(plan.regions.count, 1)
        XCTAssertEqual(plan.regions.first?.source, .manual)
        XCTAssertTrue(plan.unresolvedValues.isEmpty)
    }

    func testBuildPlanDropsRegionsContainedWithinAnother() throws {
        let pdfData = PDFTestFixtures.makePDF(containing: "Invoice")
        let analysis = RedactionFixtures.analysis(plainText: "Invoice", entities: [])

        let outer = PDFRedactionRegion(
            pageIndex: 0,
            bounds: CGRect(x: 10, y: 10, width: 100, height: 40),
            source: .manual
        )
        let inner = PDFRedactionRegion(
            pageIndex: 0,
            bounds: CGRect(x: 20, y: 20, width: 30, height: 12),
            source: .manual
        )

        let plan = try builder.buildPlan(
            analysis: analysis,
            pdfData: pdfData,
            selectedEntityIDs: [],
            manualRegions: [outer, inner]
        )

        XCTAssertEqual(plan.regions.count, 1)
        XCTAssertEqual(plan.regions.first?.bounds, outer.bounds)
    }

    func testComposePlanFiltersResolvedRegionsBySelection() {
        let entity = RedactionFixtures.entity(
            type: .email,
            value: "secret@example.com",
            in: "secret@example.com"
        )
        let autoRegion = PDFRedactionRegion(
            pageIndex: 0,
            bounds: CGRect(x: 1, y: 2, width: 3, height: 4),
            source: .detected(entityID: entity.id, value: "secret@example.com")
        )
        let manualRegion = PDFRedactionRegion(
            pageIndex: 0,
            bounds: CGRect(x: 10, y: 10, width: 40, height: 12),
            source: .manual
        )

        let selectedPlan = PDFRedactionPlanBuilder.composePlan(
            selectedEntityIDs: [entity.id],
            manualRegions: [manualRegion],
            resolvedAutoRegions: [autoRegion],
            selectedEntities: [entity]
        )

        XCTAssertEqual(selectedPlan.regions.count, 2)
        XCTAssertTrue(selectedPlan.unresolvedValues.isEmpty)

        let deselectedPlan = PDFRedactionPlanBuilder.composePlan(
            selectedEntityIDs: [],
            manualRegions: [manualRegion],
            resolvedAutoRegions: [autoRegion],
            selectedEntities: []
        )

        XCTAssertEqual(deselectedPlan.regions.count, 1)
        XCTAssertEqual(deselectedPlan.regions.first?.source, .manual)
    }

    func testBuildPlanRejectsPlainTextDocument() throws {
        let analysis = RedactionFixtures.analysis(
            plainText: "hello",
            format: .plainText,
            entities: []
        )

        XCTAssertThrowsError(
            try builder.buildPlan(
                analysis: analysis,
                pdfData: Data("hello".utf8),
                selectedEntityIDs: [],
                manualRegions: []
            )
        ) { error in
            XCTAssertEqual(error as? PDFRedactionError, .unsupportedFormat)
        }
    }

}
