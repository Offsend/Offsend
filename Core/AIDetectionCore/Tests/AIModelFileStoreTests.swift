import XCTest
import DetectionCore
@testable import AIDetectionCore

final class AIModelFileStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testModelDirectoryUsesSanitizedRepositoryID() {
        let directory = AIModelFileStore.modelDirectory(forRepositoryID: "exdsgift/NerGuard-0.3B")
        XCTAssertEqual(directory.lastPathComponent, "exdsgift__NerGuard-0.3B")
        XCTAssertTrue(directory.path.contains("Models"))
    }

    func testResolvedFileURLAllowsNestedRelativePaths() throws {
        let url = try XCTUnwrap(
            AIModelFileStore.resolvedFileURL(forRelativePath: "onnx/model.onnx", in: tempDirectory)
        )
        XCTAssertEqual(
            url.standardizedFileURL.path,
            tempDirectory.appendingPathComponent("onnx/model.onnx").standardizedFileURL.path
        )
    }

    func testResolvedFileURLRejectsParentDirectoryTraversal() {
        XCTAssertNil(
            AIModelFileStore.resolvedFileURL(
                forRelativePath: "../../Desktop/escape.txt",
                in: tempDirectory
            )
        )
        XCTAssertNil(
            AIModelFileStore.resolvedFileURL(
                forRelativePath: "foo/../../../etc/passwd",
                in: tempDirectory
            )
        )
    }

    func testResolvedFileURLRejectsAbsoluteAndHomePaths() {
        XCTAssertNil(
            AIModelFileStore.resolvedFileURL(forRelativePath: "/tmp/evil.txt", in: tempDirectory)
        )
        XCTAssertNil(
            AIModelFileStore.resolvedFileURL(forRelativePath: "~/Desktop/evil.txt", in: tempDirectory)
        )
        XCTAssertNil(
            AIModelFileStore.resolvedFileURL(forRelativePath: "", in: tempDirectory)
        )
    }

    func testResolvedFileURLAllowsSafePathsWhenRootDoesNotExistYet() throws {
        let missingRoot = tempDirectory.appendingPathComponent("missing-models", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingRoot.path))

        let url = try XCTUnwrap(
            AIModelFileStore.resolvedFileURL(forRelativePath: "model.onnx", in: missingRoot)
        )
        XCTAssertEqual(
            url.standardizedFileURL.path,
            missingRoot.appendingPathComponent("model.onnx").standardizedFileURL.path
        )
        XCTAssertNil(
            AIModelFileStore.resolvedFileURL(forRelativePath: "../escape.txt", in: missingRoot)
        )
    }
}
