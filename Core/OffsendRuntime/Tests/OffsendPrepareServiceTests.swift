import WorkspacePolicyCore
import XCTest
@testable import OffsendRuntime

final class OffsendPrepareServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeService() -> OffsendPrepareService {
        OffsendPrepareService(configuration: .default)
    }

    private func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path)
    }

    private func contents(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testCreatesMissingIgnoreFiles() throws {
        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertTrue(report.createdRelativePaths.contains(".cursorignore"))
        XCTAssertTrue(fileExists(".cursorignore"))
        XCTAssertTrue(fileExists(".claudeignore"))
        XCTAssertTrue(fileExists(".cursorindexingignore"))
    }

    func testSkipsInformationalFiles() throws {
        _ = makeService().run(directoryURL: root)

        // Informational suggestions must not be auto-created.
        XCTAssertFalse(fileExists(".gitignore"))
        XCTAssertFalse(fileExists("AGENTS.md"))
    }

    func testDryRunDoesNotWriteFiles() throws {
        let report = makeService().run(directoryURL: root, dryRun: true)

        XCTAssertTrue(report.dryRun)
        XCTAssertFalse(report.plannedCreates.isEmpty)
        XCTAssertTrue(report.plannedCreates.contains { $0.relativePath == ".cursorignore" && $0.required })
        XCTAssertTrue(report.createdRelativePaths.isEmpty)
        XCTAssertFalse(fileExists(".cursorignore"))
    }

    func testReportsNothingToPrepareWhenAlreadyPresent() throws {
        _ = makeService().run(directoryURL: root)
        let second = makeService().run(directoryURL: root)

        XCTAssertTrue(second.createdRelativePaths.isEmpty)
        XCTAssertTrue(second.plannedCreates.isEmpty)
        XCTAssertTrue(second.errors.isEmpty)
    }

    func testReportsErrorForUnavailableDirectory() {
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        let report = makeService().run(directoryURL: missing)

        XCTAssertTrue(report.hasErrors)
        XCTAssertTrue(report.createdRelativePaths.isEmpty)
    }

    func testDoesNotOverwriteExistingIgnoreFile() throws {
        let custom = "# my rules\nmy-secret.txt\n"
        try custom.write(to: root.appendingPathComponent(".cursorignore"), atomically: true, encoding: .utf8)

        let report = makeService().run(directoryURL: root)

        XCTAssertFalse(report.createdRelativePaths.contains(".cursorignore"))
        XCTAssertEqual(try contents(".cursorignore"), custom)
    }

    func testSyncPatternsAppendsExposedPatternToExistingIgnoreFile() throws {
        // An exposed secret with an existing ignore file that does not cover it.
        try "value".write(to: root.appendingPathComponent("secrets.json"), atomically: true, encoding: .utf8)
        try "# my rules\n".write(to: root.appendingPathComponent(".cursorignore"), atomically: true, encoding: .utf8)

        let report = makeService().run(directoryURL: root, syncPatterns: true)

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertTrue(report.updatedRelativePaths.contains(".cursorignore"))
        XCTAssertTrue(try contents(".cursorignore").contains("secrets.json"))
    }

    func testWithoutSyncPatternsExistingIgnoreFileIsUntouched() throws {
        let original = "# my rules\n"
        try "value".write(to: root.appendingPathComponent("secrets.json"), atomically: true, encoding: .utf8)
        try original.write(to: root.appendingPathComponent(".cursorignore"), atomically: true, encoding: .utf8)

        let report = makeService().run(directoryURL: root)

        XCTAssertFalse(report.updatedRelativePaths.contains(".cursorignore"))
        XCTAssertEqual(try contents(".cursorignore"), original)
    }

    func testSyncPatternsDryRunPreviewsUpdatesWithoutWriting() throws {
        let original = "# my rules\n"
        try "value".write(to: root.appendingPathComponent("secrets.json"), atomically: true, encoding: .utf8)
        try original.write(to: root.appendingPathComponent(".cursorignore"), atomically: true, encoding: .utf8)

        let report = makeService().run(directoryURL: root, dryRun: true, syncPatterns: true)

        XCTAssertTrue(report.updatedRelativePaths.isEmpty)
        XCTAssertTrue(report.plannedUpdates.contains { $0.relativePath == ".cursorignore" })
        XCTAssertEqual(try contents(".cursorignore"), original)
    }

    // MARK: - Managed privacy rule files

    func testCreatesManagedPrivacyRuleFilesPerEditor() throws {
        _ = makeService().run(directoryURL: root)

        XCTAssertEqual(
            try contents(".cursor/rules/offsend_privacy.mdc"),
            AIWorkspacePrivacyDefaultFixes.cursorPrivacyRuleContents + "\n"
        )
        XCTAssertEqual(
            try contents(".claude/rules/offsend_privacy.md"),
            AIWorkspacePrivacyDefaultFixes.claudePrivacyRuleContents + "\n"
        )
        XCTAssertFalse(try contents(".claude/rules/offsend_privacy.md").contains("alwaysApply"))
    }

    func testRestoresEditedManagedPrivacyRuleFile() throws {
        _ = makeService().run(directoryURL: root)
        let path = ".cursor/rules/offsend_privacy.mdc"
        try "my edits\n".write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)

        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.updatedRelativePaths.contains(path))
        XCTAssertEqual(try contents(path), AIWorkspacePrivacyDefaultFixes.cursorPrivacyRuleContents + "\n")
    }

    func testLegacyPrivacyRuleFileIsKeptAndNoDuplicateIsCreated() throws {
        let legacy = "# my legacy rule\n"
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".cursor/rules"),
            withIntermediateDirectories: true
        )
        try legacy.write(
            to: root.appendingPathComponent(".cursor/rules/privacy.mdc"),
            atomically: true,
            encoding: .utf8
        )

        _ = makeService().run(directoryURL: root)

        XCTAssertEqual(try contents(".cursor/rules/privacy.mdc"), legacy)
        XCTAssertFalse(fileExists(".cursor/rules/offsend_privacy.mdc"))
    }

    // MARK: - ignore.tools narrowing

    func testIgnoreToolsLimitsCreatedFiles() throws {
        try """
        version: 1
        ignore:
          commit: false
          tools: [cursor]
        """.write(
            to: root.appendingPathComponent(ProjectConfigLoader.filename),
            atomically: true,
            encoding: .utf8
        )

        let report = makeService().run(directoryURL: root, materializeManagedIgnore: false)

        XCTAssertTrue(report.errors.isEmpty, "\(report.errors)")
        XCTAssertTrue(fileExists(".cursorignore"))
        XCTAssertTrue(fileExists(".cursor/rules/offsend_privacy.mdc"))
        XCTAssertFalse(fileExists(".claudeignore"))
        XCTAssertFalse(fileExists(".claude/rules/offsend_privacy.md"))
        XCTAssertFalse(fileExists(".aiexclude"))
    }
}
