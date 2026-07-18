import XCTest
import WorkspacePolicyCore
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
        XCTAssertEqual(report.gitignoreUpdated, false)
        XCTAssertEqual(report.excludeUpdated, false)
    }

    func testSyncUpdatesGitignoreWhenCommitFalse() throws {
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
        XCTAssertTrue(report.gitignoreUpdated)
        XCTAssertNotNil(report.gitignorePath)
        let gitignore = try String(contentsOf: URL(fileURLWithPath: report.gitignorePath!), encoding: .utf8)
        XCTAssertTrue(gitignore.contains(".cursorignore"))
        XCTAssertTrue(gitignore.contains(".cursorindexingignore"))
        // Managed rule files are generated artifacts: exact paths only, no directories.
        XCTAssertTrue(gitignore.contains(".cursor/rules/offsend_privacy.mdc"))
        XCTAssertTrue(gitignore.contains(".claude/rules/offsend_privacy.md"))
        XCTAssertFalse(gitignore.contains(".cursor/rules/\n"))
        XCTAssertFalse(gitignore.contains(".claude/rules/\n"))
        XCTAssertTrue(gitignore.contains(
            OffsendManagedIgnoreBlock.startMarker(section: OffsendLocalGitExcludeService.ignoreFilesSection)
        ))
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
        XCTAssertFalse(second.gitignoreUpdated)
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
        XCTAssertTrue(report.gitignoreUpdated)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursorignore").path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".gitignore").path)
        )
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

    func testSyncOutsideGitRepositoryStillUpdatesGitignore() throws {
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
        XCTAssertTrue(report.gitignoreUpdated)
        XCTAssertNotNil(report.gitignorePath)
        XCTAssertFalse(report.excludeUpdated)
        XCTAssertNil(report.excludePath)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
        )
        let gitignore = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(gitignore.contains(".cursorignore"))
    }

    func testSyncRemovesGitignoreSectionWhenCommitFlipsTrue() throws {
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
        XCTAssertTrue(first.gitignoreUpdated)
        let gitignoreURL = URL(fileURLWithPath: try XCTUnwrap(first.gitignorePath))
        XCTAssertTrue(try String(contentsOf: gitignoreURL, encoding: .utf8).contains(".cursorignore"))

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
        XCTAssertTrue(second.gitignoreUpdated)
        let gitignore = try String(contentsOf: gitignoreURL, encoding: .utf8)
        XCTAssertFalse(gitignore.contains(".cursorignore"))
        XCTAssertFalse(gitignore.contains(
            OffsendManagedIgnoreBlock.startMarker(section: OffsendLocalGitExcludeService.ignoreFilesSection)
        ))
    }

    func testSyncMigratesIgnoreFilesOutOfLocalExclude() throws {
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

        // Simulate a leftover exclude section from an older offsend release.
        let seed = OffsendLocalGitExcludeService().upsertPatterns(
            [".cursorignore", ".claudeignore"],
            repositoryURL: root,
            section: OffsendLocalGitExcludeService.ignoreFilesSection
        )
        XCTAssertTrue(seed.updated)
        let excludeURL = URL(fileURLWithPath: try XCTUnwrap(seed.excludePath))
        XCTAssertTrue(try String(contentsOf: excludeURL, encoding: .utf8).contains(".cursorignore"))

        let report = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))
        XCTAssertTrue(report.gitignoreUpdated)
        XCTAssertTrue(report.excludeUpdated)

        let gitignore = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(gitignore.contains(".cursorignore"))
        let exclude = try String(contentsOf: excludeURL, encoding: .utf8)
        XCTAssertFalse(exclude.contains(".cursorignore"))
        XCTAssertFalse(exclude.contains(
            OffsendManagedIgnoreBlock.startMarker(section: OffsendLocalGitExcludeService.ignoreFilesSection)
        ))
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
        XCTAssertTrue(sync.gitignoreUpdated)

        // Simulate `offsend hook install` with hooks.publish: false.
        let hookReport = OffsendLocalGitExcludeService().upsertPatterns(
            OffsendLocalGitExcludeService.aiHookExcludePatterns(configRelativePaths: [".cursor/hooks.json"]),
            repositoryURL: root,
            section: OffsendLocalGitExcludeService.hooksSection,
            merge: true
        )
        XCTAssertTrue(hookReport.updated)

        let excludeURL = URL(fileURLWithPath: try XCTUnwrap(hookReport.excludePath))
        var exclude = try String(contentsOf: excludeURL, encoding: .utf8)
        XCTAssertTrue(exclude.contains(".offsend/hooks/"))
        XCTAssertFalse(
            exclude.contains(
                OffsendManagedIgnoreBlock.startMarker(section: OffsendLocalGitExcludeService.ignoreFilesSection)
            ),
            "sync must migrate ignore-files out of exclude"
        )

        // Re-running sync must not wipe the hooks section.
        _ = OffsendIgnoreSyncService().run(directoryURL: root)
        exclude = try String(contentsOf: excludeURL, encoding: .utf8)
        XCTAssertTrue(exclude.contains(".offsend/hooks/"))
        let gitignore = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(gitignore.contains(".cursorignore"))
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

    func testSyncPutsDefaultsInManagedBlockWithoutDuplicatingPlainLines() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns:
                - ".env*"
                - "*.pem"
            """
        )

        let report = OffsendIgnoreSyncService().run(directoryURL: root)
        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))
        let cursor = try String(contentsOf: root.appendingPathComponent(".cursorignore"), encoding: .utf8)
        XCTAssertTrue(cursor.contains(OffsendManagedIgnoreBlock.startMarker))
        XCTAssertTrue(cursor.contains(".env*"))
        XCTAssertTrue(cursor.contains("*.pem"))
        // Patterns must appear once (inside managed block), not also as plain seed lines.
        XCTAssertEqual(cursor.components(separatedBy: ".env*").count - 1, 1)
        XCTAssertEqual(cursor.components(separatedBy: "*.pem").count - 1, 1)
    }

    func testSyncMigratesStockPlainTemplateIntoManagedBlock() throws {
        try AIWorkspacePrivacyIgnoreTemplate.contents.write(
            to: root.appendingPathComponent(".cursorignore"),
            atomically: true,
            encoding: .utf8
        )
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns:
                - ".env*"
                - "*.pem"
                - "custom-secret/"
            """
        )

        _ = OffsendIgnoreSyncService().run(directoryURL: root)
        let cursor = try String(contentsOf: root.appendingPathComponent(".cursorignore"), encoding: .utf8)
        XCTAssertTrue(cursor.contains("custom-secret/"))
        XCTAssertTrue(cursor.contains(OffsendManagedIgnoreBlock.startMarker))
        XCTAssertEqual(cursor.components(separatedBy: ".env*").count - 1, 1)
    }

    func testSyncHonorsIgnoreTools() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              tools: [cursor]
              patterns:
                - "secrets/"
            """
        )

        let report = OffsendIgnoreSyncService().run(directoryURL: root)

        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))
        XCTAssertTrue(report.createdRelativePaths.contains(".cursorignore"))
        XCTAssertFalse(report.createdRelativePaths.contains(".claudeignore"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".claudeignore").path))

        // The managed .gitignore section only lists files Offsend actually manages here.
        let gitignore = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(gitignore.contains(".cursorignore"))
        XCTAssertTrue(gitignore.contains(".cursor/rules/offsend_privacy.mdc"))
        XCTAssertFalse(gitignore.contains(".claudeignore"))
        XCTAssertFalse(gitignore.contains(".claude/rules/offsend_privacy.md"))
    }

    func testSyncTreatsUnknownToolsAsAllTools() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              tools: [nonexistent-editor]
              patterns:
                - "secrets/"
            """
        )

        let report = OffsendIgnoreSyncService().run(directoryURL: root)

        XCTAssertTrue(report.errors.isEmpty, report.errors.joined(separator: "; "))
        XCTAssertTrue(report.createdRelativePaths.contains(".cursorignore"))
        XCTAssertTrue(report.createdRelativePaths.contains(".claudeignore"))
    }

    func testGitignorePreservesUserLines() throws {
        try "# keep me\nbuild/\n".write(
            to: root.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try writeConfig(
            """
            version: 1
            ignore:
              commit: false
              patterns:
                - "secrets/"
            """
        )

        _ = OffsendIgnoreSyncService().run(directoryURL: root)
        let gitignore = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(gitignore.contains("# keep me"))
        XCTAssertTrue(gitignore.contains("build/"))
        XCTAssertTrue(gitignore.contains(".cursorignore"))
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
