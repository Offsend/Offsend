import XCTest
@testable import DocumentCore

final class DocumentProcessingLimitsTests: XCTestCase {
    func testFreeMaximumFileByteCountIs15Megabytes() {
        XCTAssertEqual(DocumentProcessingLimits.freeMaximumFileByteCount, 15_728_640)
    }

    func testProMaximumFileByteCountIs50Megabytes() {
        XCTAssertEqual(DocumentProcessingLimits.proMaximumFileByteCount, 52_428_800)
    }

    func testMaximumFileByteCountSelectsTier() {
        XCTAssertEqual(DocumentProcessingLimits.maximumFileByteCount(isPro: false), 15_728_640)
        XCTAssertEqual(DocumentProcessingLimits.maximumFileByteCount(isPro: true), 52_428_800)
    }

    func testDefaultDocumentProcessingOptionsUseFreeLimit() {
        XCTAssertEqual(
            DocumentProcessingOptions.default.maximumFileByteCount,
            DocumentProcessingLimits.freeMaximumFileByteCount
        )
    }
}
