import XCTest
import DetectionCore
@testable import AIDetectionCore

final class HuggingFaceRepositoryTests: XCTestCase {
    func testParsesBareRepositoryID() {
        XCTAssertEqual(HuggingFaceRepository.parseRepositoryID("exdsgift/NerGuard-0.3B"), "exdsgift/NerGuard-0.3B")
    }

    func testParsesHuggingFaceURL() {
        XCTAssertEqual(
            HuggingFaceRepository.parseRepositoryID("https://huggingface.co/exdsgift/NerGuard-0.3B"),
            "exdsgift/NerGuard-0.3B"
        )
    }

    func testParsesHuggingFaceURLWithTrailingSlash() {
        XCTAssertEqual(
            HuggingFaceRepository.parseRepositoryID("https://huggingface.co/dslim/bert-base-NER/"),
            "dslim/bert-base-NER"
        )
    }

    func testRejectsDatasetURL() {
        XCTAssertNil(HuggingFaceRepository.parseRepositoryID("https://huggingface.co/datasets/some/set"))
    }

    func testRejectsInvalidInput() {
        XCTAssertNil(HuggingFaceRepository.parseRepositoryID("not-a-model"))
        XCTAssertNil(HuggingFaceRepository.parseRepositoryID(""))
    }

    func testDirectoryNameSanitizesSlash() {
        XCTAssertEqual(
            HuggingFaceRepository.directoryName(for: "exdsgift/NerGuard-0.3B"),
            "exdsgift__NerGuard-0.3B"
        )
    }
}
