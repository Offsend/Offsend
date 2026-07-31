import DetectionCore
import PDFKit
import XCTest
@testable import DocumentCore

final class PDFRedactionRegionResolverTests: XCTestCase {
    private let resolver = PDFRedactionRegionResolver()

    func testResolvesValueIgnoringDiacritics() throws {
        let pdfData = PDFTestFixtures.makePDF(containing: "Client Renée Dupont")
        let entity = RedactionFixtures.entity(type: .customClient, value: "Renee Dupont", in: "Renee Dupont")

        let regions = try resolver.resolveRegions(in: pdfData, entities: [entity], padding: 1)

        XCTAssertEqual(regions.count, 1)
        guard case let .detected(entityID, value) = regions.first?.source else {
            return XCTFail("Expected a detected region source")
        }
        XCTAssertEqual(entityID, entity.id)
        XCTAssertEqual(value, "Renee Dupont")
    }

    func testReturnsNoRegionsWhenValueAbsent() throws {
        let pdfData = PDFTestFixtures.makePDF(containing: "Nothing sensitive here")
        let entity = RedactionFixtures.entity(type: .email, value: "absent@example.com", in: "absent@example.com")

        let regions = try resolver.resolveRegions(in: pdfData, entities: [entity], padding: 1)

        XCTAssertTrue(regions.isEmpty)
    }
}
