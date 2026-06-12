import XCTest
@testable import AIDetectionCore

final class HuggingFaceTokenStoreTests: XCTestCase {
    func testMaskedPreviewShowsHuggingFacePrefixAndSuffix() {
        let preview = HuggingFaceTokenStore.maskedPreview(for: "hf_abcdefghijklmnopqrstuvwxyzmTac")
        XCTAssertEqual(preview, "hf_...mTac")
    }

    func testMaskedPreviewUsesGenericPrefixForNonHFTokens() {
        let preview = HuggingFaceTokenStore.maskedPreview(for: "abcdEFGHijklmnop")
        XCTAssertEqual(preview, "abcd...mnop")
    }

    func testMaskedPreviewFallsBackForVeryShortTokens() {
        let preview = HuggingFaceTokenStore.maskedPreview(for: "hf_ab")
        XCTAssertEqual(preview, "•••••")
    }
}
