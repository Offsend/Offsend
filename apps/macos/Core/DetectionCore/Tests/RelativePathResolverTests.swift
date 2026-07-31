import XCTest
import DetectionCore

final class RelativePathResolverTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testAllowsNestedRelativePaths() throws {
        let url = try XCTUnwrap(
            RelativePathResolver.resolvedFileURL(forRelativePath: "onnx/model.onnx", in: tempDirectory)
        )
        XCTAssertEqual(
            url.standardizedFileURL.path,
            tempDirectory.appendingPathComponent("onnx/model.onnx").standardizedFileURL.path
        )
    }

    func testRejectsTraversalAbsoluteAndHomePaths() {
        XCTAssertNil(
            RelativePathResolver.resolvedFileURL(forRelativePath: "../../escape.txt", in: tempDirectory)
        )
        XCTAssertNil(
            RelativePathResolver.resolvedFileURL(forRelativePath: "/tmp/evil.txt", in: tempDirectory)
        )
        XCTAssertNil(
            RelativePathResolver.resolvedFileURL(forRelativePath: "~/Desktop/evil.txt", in: tempDirectory)
        )
        XCTAssertNil(
            RelativePathResolver.resolvedFileURL(forRelativePath: #"C:\Windows\evil.txt"#, in: tempDirectory)
        )
    }

    func testAllowsSafePathsWhenRootDoesNotExistYet() throws {
        let missingRoot = tempDirectory.appendingPathComponent("missing", isDirectory: true)
        let url = try XCTUnwrap(
            RelativePathResolver.resolvedFileURL(forRelativePath: "model.onnx", in: missingRoot)
        )
        XCTAssertEqual(
            url.standardizedFileURL.path,
            missingRoot.appendingPathComponent("model.onnx").standardizedFileURL.path
        )
        XCTAssertNil(
            RelativePathResolver.resolvedFileURL(forRelativePath: "../escape.txt", in: missingRoot)
        )
    }
}
