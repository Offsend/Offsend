import XCTest
import DetectionCore
@testable import AIDetectionCore

final class NERLabelMapperTests: XCTestCase {
    func testMapsPersonLabels() {
        XCTAssertEqual(NERLabelMapper.defaultEntityType(for: "GIVENNAME"), .personName)
        XCTAssertEqual(NERLabelMapper.defaultEntityType(for: "B-PER"), .personName)
    }

    func testMapsEmailAndGovernmentId() {
        XCTAssertEqual(NERLabelMapper.defaultEntityType(for: "EMAIL"), .email)
        XCTAssertEqual(NERLabelMapper.defaultEntityType(for: "PASSPORTNUM"), .governmentId)
    }
}
