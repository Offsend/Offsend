import XCTest
@testable import OffsendRuntime

final class PromptReadGateExcludeTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testExcludedProjectPathSkipsGate() {
        XCTAssertTrue(
            PromptReadGate.isExcluded(
                path: root.appendingPathComponent("docs/cli.md").path,
                excludePatterns: ["docs/**"],
                projectRoot: root
            )
        )
    }

    func testNonMatchingPathIsNotExcluded() {
        XCTAssertFalse(
            PromptReadGate.isExcluded(
                path: root.appendingPathComponent("src/main.swift").path,
                excludePatterns: ["docs/**"],
                projectRoot: root
            )
        )
    }

    func testEmptyPatternsNeverExclude() {
        XCTAssertFalse(
            PromptReadGate.isExcluded(
                path: root.appendingPathComponent("docs/cli.md").path,
                excludePatterns: [],
                projectRoot: root
            )
        )
    }

    func testPathOutsideProjectRootIsNotExcluded() {
        XCTAssertFalse(
            PromptReadGate.isExcluded(
                path: "/etc/hosts",
                excludePatterns: ["**"],
                projectRoot: root
            )
        )
    }

    func testSymlinkToNonExcludedTargetIsNotExcluded() throws {
        // A benign excluded link name must not smuggle a sensitive target past the gate.
        let envFile = root.appendingPathComponent(".env")
        try "placeholder".write(to: envFile, atomically: true, encoding: .utf8)
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let link = docs.appendingPathComponent("notes.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: envFile)

        XCTAssertFalse(
            PromptReadGate.isExcluded(
                path: link.path,
                excludePatterns: ["docs/**"],
                projectRoot: root
            )
        )
    }

    func testSymlinkWithinExcludedTreeIsExcluded() throws {
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let target = docs.appendingPathComponent("real.md")
        try "text".write(to: target, atomically: true, encoding: .utf8)
        let link = docs.appendingPathComponent("alias.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertTrue(
            PromptReadGate.isExcluded(
                path: link.path,
                excludePatterns: ["docs/**"],
                projectRoot: root
            )
        )
    }
}
