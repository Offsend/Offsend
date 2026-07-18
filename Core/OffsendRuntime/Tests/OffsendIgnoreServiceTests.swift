import WorkspacePolicyCore
import XCTest
@testable import OffsendRuntime

final class OffsendIgnoreServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeService() -> OffsendIgnoreService {
        OffsendIgnoreService(configuration: .default)
    }

    private func write(_ contents: String, to relativePath: String) throws {
        try contents.write(
            to: root.appendingPathComponent(relativePath),
            atomically: true,
            encoding: .utf8
        )
    }

    private func contents(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path)
    }

    // MARK: - Updating existing files

    func testAppendsPatternToExistingIgnoreFilesOnly() throws {
        try write("# mine\n", to: ".cursorignore")
        try write("# mine\n", to: ".claudeignore")

        let report = makeService().run(directoryURL: root, patterns: ["secrets/prod.json"])

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertEqual(report.updatedRelativePaths, [".claudeignore", ".cursorignore"])
        XCTAssertTrue(report.createdRelativePaths.isEmpty)
        XCTAssertTrue(try contents(".cursorignore").contains("secrets/prod.json"))
        XCTAssertTrue(try contents(".claudeignore").contains("secrets/prod.json"))
        // Files that did not exist stay absent.
        XCTAssertFalse(fileExists(".aiexclude"))
        XCTAssertFalse(fileExists(".gitignore"))
    }

    func testSecondRunIsUnchanged() throws {
        try write("# mine\n", to: ".cursorignore")

        _ = makeService().run(directoryURL: root, patterns: ["*.pem"])
        let second = makeService().run(directoryURL: root, patterns: ["*.pem"])

        XCTAssertTrue(second.updatedRelativePaths.isEmpty)
        XCTAssertEqual(second.unchangedRelativePaths, [".cursorignore"])
        XCTAssertTrue(second.errors.isEmpty)
    }

    func testNeverTouchesGitignore() throws {
        try write("node_modules/\n", to: ".gitignore")
        try write("# mine\n", to: ".cursorignore")

        _ = makeService().run(directoryURL: root, patterns: ["*.pem"])

        XCTAssertEqual(try contents(".gitignore"), "node_modules/\n")
    }

    // MARK: - Creating the standard set

    func testCreatesStandardSetWhenNoIgnoreFilesExist() throws {
        let report = makeService().run(directoryURL: root, patterns: ["secrets/prod.json"])

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertTrue(report.createdRelativePaths.contains(".cursorignore"))
        XCTAssertTrue(report.createdRelativePaths.contains(".claudeignore"))
        // Without project config, created files still get the full template plus the pattern.
        // With `.offsend.yml`, sync owns defaults via ignore.patterns managed block.
        let cursorignore = try contents(".cursorignore")
        XCTAssertTrue(cursorignore.contains(".env*"))
        XCTAssertTrue(cursorignore.contains("secrets/prod.json"))
        // Non-ignore files are not created.
        XCTAssertFalse(fileExists(".gitignore"))
        XCTAssertFalse(fileExists(".cursor/rules/offsend_privacy.mdc"))
        XCTAssertFalse(fileExists(".claude/rules/offsend_privacy.md"))
    }

    // MARK: - Pattern normalization

    func testDirectoryPatternGetsTrailingSlash() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("secrets"),
            withIntermediateDirectories: true
        )
        try write("# mine\n", to: ".cursorignore")

        let report = makeService().run(directoryURL: root, patterns: ["secrets"])

        XCTAssertEqual(report.patterns, ["secrets/"])
        XCTAssertTrue(try contents(".cursorignore").contains("secrets/\n"))
    }

    func testAbsolutePathUnderRootBecomesRelative() throws {
        try write("# mine\n", to: ".cursorignore")

        let absolute = root.appendingPathComponent("config/prod.json").path
        let report = makeService().run(directoryURL: root, patterns: [absolute])

        XCTAssertEqual(report.patterns, ["config/prod.json"])
    }

    func testAbsolutePathOutsideRootIsAnError() throws {
        try write("# mine\n", to: ".cursorignore")

        let report = makeService().run(directoryURL: root, patterns: ["/etc/passwd"])

        XCTAssertTrue(report.hasErrors)
        XCTAssertTrue(report.updatedRelativePaths.isEmpty)
    }

    func testStripsDotSlashAndDeduplicates() throws {
        try write("# mine\n", to: ".cursorignore")

        let report = makeService().run(
            directoryURL: root,
            patterns: ["./a.pem", "a.pem", "  ", ""]
        )

        XCTAssertEqual(report.patterns, ["a.pem"])
    }

    // MARK: - Dry run

    func testDryRunDoesNotWrite() throws {
        try write("# mine\n", to: ".cursorignore")

        let report = makeService().run(
            directoryURL: root,
            patterns: ["*.pem"],
            dryRun: true
        )

        XCTAssertTrue(report.dryRun)
        XCTAssertEqual(
            report.plannedUpdates,
            [IgnorePlannedUpdate(relativePath: ".cursorignore", addedLines: ["*.pem"])]
        )
        XCTAssertTrue(report.updatedRelativePaths.isEmpty)
        XCTAssertFalse(try contents(".cursorignore").contains("*.pem"))
    }

    func testDryRunPlansCreatesWhenNoIgnoreFilesExist() throws {
        let report = makeService().run(
            directoryURL: root,
            patterns: ["*.pem"],
            dryRun: true
        )

        XCTAssertTrue(report.plannedCreates.contains(".cursorignore"))
        XCTAssertFalse(fileExists(".cursorignore"))
    }

    // MARK: - Errors

    func testMissingDirectoryReportsError() {
        let missing = root.appendingPathComponent("nope", isDirectory: true)
        let report = makeService().run(directoryURL: missing, patterns: ["*.pem"])

        XCTAssertTrue(report.hasErrors)
    }

    func testNoUsablePatternsReportsError() throws {
        try write("# mine\n", to: ".cursorignore")

        let report = makeService().run(directoryURL: root, patterns: ["  ", "# comment"])

        XCTAssertTrue(report.hasErrors)
    }
}
