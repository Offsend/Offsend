import DetectionCore
import RiskScoringCore
import XCTest
@testable import DocumentCore

final class PDFRedactionExporterTests: XCTestCase {
    private let exporter = PDFRedactionExporter()

    func testExportRejectsUnresolvedValuesByDefault() throws {
        let email = "missing-from-layout@example.com"
        let pdfData = PDFTestFixtures.makePDF(containing: "Invoice total $100")
        let entity = RedactionFixtures.entity(type: .email, value: email, in: "Invoice for \(email)")
        let analysis = RedactionFixtures.analysis(
            plainText: "Invoice for \(email)",
            entities: [entity]
        )
        let session = PDFRedactionSession(
            sourceData: pdfData,
            analysis: analysis,
            selectedEntityIDs: Set([entity.id]),
            manualRegions: []
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        XCTAssertThrowsError(try exporter.export(session: session, to: destination)) { error in
            XCTAssertEqual(error as? PDFRedactionError, .unresolvedValues([email]))
        }
    }

    func testExportAllowsUnresolvedValuesWhenExplicitlyOptedIn() throws {
        let email = "missing-from-layout@example.com"
        let pdfData = PDFTestFixtures.makePDF(containing: "Invoice total $100")
        let manualRegion = PDFRedactionRegion(
            pageIndex: 0,
            bounds: CGRect(x: 72, y: 672, width: 160, height: 14),
            source: .manual
        )
        let entity = RedactionFixtures.entity(type: .email, value: email, in: "Invoice for \(email)")
        let analysis = RedactionFixtures.analysis(
            plainText: "Invoice for \(email)",
            entities: [entity]
        )
        let session = PDFRedactionSession(
            sourceData: pdfData,
            analysis: analysis,
            selectedEntityIDs: Set([entity.id]),
            manualRegions: [manualRegion],
            allowExportWithUnresolvedValues: true
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: destination) }

        let result = try exporter.export(session: session, to: destination)

        XCTAssertFalse(result.redactedData.isEmpty)
        XCTAssertEqual(result.warnings, [.valueNotFoundInPDF(email)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

}
