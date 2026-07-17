import XCTest
@testable import OffsendRuntime

final class OffsendManagedIgnoreDriftTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testNoFindingsWhenNoIgnoreFilesExist() {
        let findings = OffsendManagedIgnoreDrift.findings(
            directoryURL: root,
            patterns: ["secrets/"]
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testReportsMissingPatternInManagedBlock() throws {
        let contents = """
        # >>> offsend managed
        a/
        # <<< offsend managed
        """
        try contents.write(
            to: root.appendingPathComponent(".cursorignore"),
            atomically: true,
            encoding: .utf8
        )

        let findings = OffsendManagedIgnoreDrift.findings(
            directoryURL: root,
            patterns: ["a/", "b/"]
        )
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.relativePath, ".cursorignore")
        XCTAssertEqual(findings.first?.missingPatterns, ["b/"])
    }

    func testFallsBackToWholeFileWhenNoManagedBlock() throws {
        try "secrets/\n".write(
            to: root.appendingPathComponent(".cursorignore"),
            atomically: true,
            encoding: .utf8
        )

        let findings = OffsendManagedIgnoreDrift.findings(
            directoryURL: root,
            patterns: ["secrets/"]
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testEmptyPatternsProduceNoFindings() throws {
        try "x/\n".write(
            to: root.appendingPathComponent(".cursorignore"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(
            OffsendManagedIgnoreDrift.findings(directoryURL: root, patterns: []).isEmpty
        )
    }
}
