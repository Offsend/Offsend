import XCTest
@testable import OffsendRuntime

final class OffsendIgnoreSyncServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSyncWritesManagedBlock() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns:
                - "secrets/"
            """
        )

        let report = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))
        XCTAssertFalse(report.createdRelativePaths.isEmpty)
        let cursor = try String(contentsOf: root.appendingPathComponent(".cursorignore"), encoding: .utf8)
        XCTAssertTrue(cursor.contains(OffsendManagedIgnoreBlock.startMarker))
        XCTAssertTrue(cursor.contains("secrets/"))
        XCTAssertEqual(report.excludeUpdated, false)
    }

    func testSyncUpdatesGitExcludeWhenCommitFalse() throws {
        // Initialize a real git repo so info/exclude resolves.
        try runGit(["init"])
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              patterns:
                - "secrets/"
            """
        )

        let report = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))
        XCTAssertTrue(report.excludeUpdated)
        XCTAssertNotNil(report.excludePath)
        let exclude = try String(contentsOf: URL(fileURLWithPath: report.excludePath!), encoding: .utf8)
        XCTAssertTrue(exclude.contains(".cursorignore"))
        XCTAssertTrue(exclude.contains(OffsendManagedIgnoreBlock.startMarker))
    }

    func testPromotePatternsUpdatesYAMLThenSync() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns: []
            hooks:
              type: pre-commit
            """
        )

        let result = OffsendIgnoreSyncService().promotePatterns(
            ["team-secret/"],
            directoryURL: root
        )
        XCTAssertEqual(result.added, ["team-secret/"])
        XCTAssertTrue(result.sync.errors.isEmpty, result.sync.errors.joined(separator: "; "))
        let yaml = try String(
            contentsOf: root.appendingPathComponent(ProjectConfigLoader.filename),
            encoding: .utf8
        )
        XCTAssertTrue(yaml.contains("team-secret/"))
        let cursor = try String(contentsOf: root.appendingPathComponent(".cursorignore"), encoding: .utf8)
        XCTAssertTrue(cursor.contains("team-secret/"))
    }

    func testPreservesUserLinesOnSync() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns:
                - "managed/"
            """
        )
        try "# personal\nlocal-only/\n".write(
            to: root.appendingPathComponent(".cursorignore"),
            atomically: true,
            encoding: .utf8
        )

        _ = OffsendIgnoreSyncService().run(directoryURL: root)
        let cursor = try String(contentsOf: root.appendingPathComponent(".cursorignore"), encoding: .utf8)
        XCTAssertTrue(cursor.contains("local-only/"))
        XCTAssertTrue(cursor.contains("managed/"))
        XCTAssertTrue(cursor.contains("# personal"))
    }

    func testSyncIsIdempotent() throws {
        try runGit(["init"])
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              patterns:
                - "secrets/"
            """
        )

        let first = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(first.errors.isEmpty, first.errors.joined(separator: "; "))

        let second = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(second.errors.isEmpty, second.errors.joined(separator: "; "))
        XCTAssertTrue(second.createdRelativePaths.isEmpty)
        XCTAssertTrue(second.updatedRelativePaths.isEmpty)
        XCTAssertFalse(second.excludeUpdated)
        XCTAssertFalse(second.unchangedRelativePaths.isEmpty)
    }

    func testSyncReportsMalformedBlockAndPreservesFile() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns:
                - "secrets/"
            """
        )
        let broken = "# user\n\(OffsendManagedIgnoreBlock.startMarker)\norphan/\n"
        let cursorURL = root.appendingPathComponent(".cursorignore")
        try broken.write(to: cursorURL, atomically: true, encoding: .utf8)

        let report = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(report.hasErrors)
        XCTAssertTrue(report.errors.contains { $0.contains(".cursorignore") })
        let after = try String(contentsOf: cursorURL, encoding: .utf8)
        XCTAssertEqual(after, broken)
    }

    func testDryRunWritesNothing() throws {
        try runGit(["init"])
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              patterns:
                - "secrets/"
            """
        )

        let report = OffsendIgnoreSyncService().run(directoryURL: root, dryRun: true)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))
        XCTAssertFalse(report.createdRelativePaths.isEmpty)
        XCTAssertTrue(report.excludeUpdated)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursorignore").path)
        )
        // `git init` may pre-create .git/info/exclude; dry run must not add the block.
        let excludeURL = root.appendingPathComponent(".git/info/exclude")
        if let exclude = try? String(contentsOf: excludeURL, encoding: .utf8) {
            XCTAssertFalse(exclude.contains(OffsendManagedIgnoreBlock.startMarker))
        }
    }

    func testPromotePatternsDryRunDoesNotModifyConfig() throws {
        let yaml = """
        version: 1
        ignore:
          commit: true
          patterns: []
        """
        try writeConfig(yaml)

        let result = OffsendIgnoreSyncService().promotePatterns(
            ["team-secret/"],
            directoryURL: root,
            dryRun: true
        )
        XCTAssertEqual(result.added, ["team-secret/"])
        let after = try String(
            contentsOf: root.appendingPathComponent(ProjectConfigLoader.filename),
            encoding: .utf8
        )
        XCTAssertEqual(after, yaml)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursorignore").path)
        )
    }

    func testPromotePatternsWithoutConfigReportsError() throws {
        let result = OffsendIgnoreSyncService().promotePatterns(
            ["secrets/"],
            directoryURL: root
        )
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertNil(result.configPath)
        XCTAssertTrue(result.sync.errors.contains { $0.contains("offsend init") })
        // Failure must not leave side effects behind.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursorignore").path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
        )
    }

    func testSyncWithoutConfigReportsErrorAndWritesNothing() throws {
        let report = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(report.hasErrors)
        XCTAssertTrue(report.errors.contains { $0.contains("offsend init") })
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursorignore").path)
        )
    }

    func testSyncOutsideGitRepositoryDoesNotCreateGitDirectory() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              patterns:
                - "secrets/"
            """
        )

        let report = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))
        XCTAssertFalse(report.excludeUpdated)
        XCTAssertNil(report.excludePath)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
        )
    }

    func testSyncRemovesExcludeSectionWhenCommitFlipsTrue() throws {
        try runGit(["init"])
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              patterns:
                - "secrets/"
            """
        )
        let first = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(first.excludeUpdated)
        let excludeURL = URL(fileURLWithPath: try XCTUnwrap(first.excludePath))
        XCTAssertTrue(try String(contentsOf: excludeURL, encoding: .utf8).contains(".cursorignore"))

        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns:
                - "secrets/"
            """
        )
        let second = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(second.errors.isEmpty, second.errors.joined(separator: "; "))
        XCTAssertTrue(second.excludeUpdated)
        let exclude = try String(contentsOf: excludeURL, encoding: .utf8)
        XCTAssertFalse(exclude.contains(".cursorignore"))
        XCTAssertFalse(exclude.contains(OffsendManagedIgnoreBlock.startMarker(section: "ignore-files")))
    }

    func testSyncAndHookExcludeSectionsCoexist() throws {
        try runGit(["init"])
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              patterns:
                - "secrets/"
            """
        )

        let sync = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(sync.excludeUpdated)

        // Simulate `offsend hook install` with hooks.publish: false.
        let hookReport = OffsendLocalGitExcludeService().upsertPatterns(
            OffsendLocalGitExcludeService.aiHookExcludePatterns(configRelativePaths: [".cursor/hooks.json"]),
            repositoryURL: root,
            section: OffsendLocalGitExcludeService.hooksSection,
            merge: true
        )
        XCTAssertTrue(hookReport.updated)

        let excludeURL = URL(fileURLWithPath: try XCTUnwrap(sync.excludePath))
        var exclude = try String(contentsOf: excludeURL, encoding: .utf8)
        XCTAssertTrue(exclude.contains(".cursorignore"), "hook install must not wipe sync entries")
        XCTAssertTrue(exclude.contains(".offsend/hooks/"))

        // Re-running sync must not wipe the hooks section either.
        _ = OffsendIgnoreSyncService().run(directoryURL: root)
        exclude = try String(contentsOf: excludeURL, encoding: .utf8)
        XCTAssertTrue(exclude.contains(".cursorignore"))
        XCTAssertTrue(exclude.contains(".offsend/hooks/"))
    }

    func testHookExcludeMergeAccumulatesTargets() throws {
        try runGit(["init"])
        let service = OffsendLocalGitExcludeService()
        _ = service.upsertPatterns(
            OffsendLocalGitExcludeService.aiHookExcludePatterns(configRelativePaths: [".cursor/hooks.json"]),
            repositoryURL: root,
            section: OffsendLocalGitExcludeService.hooksSection,
            merge: true
        )
        _ = service.upsertPatterns(
            OffsendLocalGitExcludeService.aiHookExcludePatterns(configRelativePaths: [".claude/settings.json"]),
            repositoryURL: root,
            section: OffsendLocalGitExcludeService.hooksSection,
            merge: true
        )
        let excludeURL = root.appendingPathComponent(".git/info/exclude")
        let exclude = try String(contentsOf: excludeURL, encoding: .utf8)
        XCTAssertTrue(exclude.contains(".cursor/hooks.json"))
        XCTAssertTrue(exclude.contains(".claude/settings.json"))
    }

    func testExcludeServiceSkipsOutsideGitRepository() {
        let report = OffsendLocalGitExcludeService().upsertPatterns(
            [".cursorignore"],
            repositoryURL: root,
            section: OffsendLocalGitExcludeService.ignoreFilesSection
        )
        XCTAssertTrue(report.skippedNotARepository)
        XCTAssertFalse(report.updated)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
        )
    }

    func testPromoteOutsideRootPatternReportsError() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns: []
            """
        )
        let result = OffsendIgnoreSyncService().promotePatterns(
            ["/etc/passwd"],
            directoryURL: root
        )
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertTrue(result.sync.errors.contains { $0.contains("outside the target directory") })
        // Config must stay untouched on failure.
        let yaml = try String(
            contentsOf: root.appendingPathComponent(ProjectConfigLoader.filename),
            encoding: .utf8
        )
        XCTAssertFalse(yaml.contains("passwd"))
    }

    func testPromoteBlankPatternsReportsNoPatternsToAdd() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns: []
            """
        )
        let result = OffsendIgnoreSyncService().promotePatterns(
            ["   ", "# comment"],
            directoryURL: root
        )
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertTrue(result.sync.errors.contains("No patterns to add."))
    }

    func testPromoteFromSubdirectoryAnchorsToRepositoryRoot() throws {
        try runGit(["init"])
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns: []
            """
        )
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sub.appendingPathComponent("secrets", isDirectory: true),
            withIntermediateDirectories: true
        )

        let result = OffsendIgnoreSyncService().promotePatterns(
            ["secrets"],
            directoryURL: sub
        )
        XCTAssertEqual(result.added, ["sub/secrets/"])

        let yaml = try String(
            contentsOf: root.appendingPathComponent(ProjectConfigLoader.filename),
            encoding: .utf8
        )
        XCTAssertTrue(yaml.contains("sub/secrets/"))
        // Ignore files materialize at the repository root, not the subdirectory.
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursorignore").path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sub.appendingPathComponent(".cursorignore").path)
        )
    }

    private func writeConfig(_ yaml: String) throws {
        try yaml.write(
            to: root.appendingPathComponent(ProjectConfigLoader.filename),
            atomically: true,
            encoding: .utf8
        )
    }

    private func runGit(_ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
