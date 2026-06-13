import XCTest
import DetectionCore
@testable import AIDetectionCore

final class AIModelFileStoreTests: XCTestCase {
    func testModelDirectoryUsesSanitizedRepositoryID() {
        let directory = AIModelFileStore.modelDirectory(forRepositoryID: "exdsgift/NerGuard-0.3B")
        XCTAssertEqual(directory.lastPathComponent, "exdsgift__NerGuard-0.3B")
        XCTAssertTrue(directory.path.contains("Models"))
    }
}
