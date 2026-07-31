import Foundation
import XCTest
@testable import WorkspacePolicyCore

final class OffsendProjectIgnoreSettingsTests: XCTestCase {
    func testParseDefaultsWhenIgnoreSectionAbsent() {
        let settings = OffsendProjectIgnoreSettings.parse(
            """
            version: 1

            check:
              fail_on: block
            """
        )
        XCTAssertFalse(settings.commitIgnoreFiles)
        XCTAssertNil(settings.toolIDs)
    }

    func testParseCommitTrue() {
        let settings = OffsendProjectIgnoreSettings.parse(
            """
            version: 1

            ignore:
              commit: true
              patterns: []
            """
        )
        XCTAssertTrue(settings.commitIgnoreFiles)
        XCTAssertNil(settings.toolIDs)
    }

    func testParseBlockToolsListAndCommitFalse() {
        let settings = OffsendProjectIgnoreSettings.parse(
            """
            version: 1

            ignore:
              commit: false
              tools:
                - cursor
                - "claude"
              patterns:
                - ".env*"
                - "*.pem"
            """
        )
        XCTAssertFalse(settings.commitIgnoreFiles)
        XCTAssertEqual(settings.toolIDs, [.cursor, .claude])
    }

    func testParseFlowToolsList() {
        let settings = OffsendProjectIgnoreSettings.parse(
            """
            ignore:
              tools: [cursor, windsurf]
            """
        )
        XCTAssertEqual(settings.toolIDs, [.cursor, .windsurf])
    }

    func testParseIgnoresUnknownToolSlugsAndComments() {
        let settings = OffsendProjectIgnoreSettings.parse(
            """
            ignore:
              commit: false # keep files out of git
              tools:
                # narrowed on purpose
                - not-a-tool
            """
        )
        XCTAssertFalse(settings.commitIgnoreFiles)
        XCTAssertNil(settings.toolIDs)
    }

    func testParsePatternListItemsAreNotCollectedAsTools() {
        let settings = OffsendProjectIgnoreSettings.parse(
            """
            ignore:
              patterns:
                - "cursor"
              commit: true
            """
        )
        XCTAssertTrue(settings.commitIgnoreFiles)
        XCTAssertNil(settings.toolIDs)
    }

    func testParseIgnoresKeysOutsideIgnoreSection() {
        let settings = OffsendProjectIgnoreSettings.parse(
            """
            hooks:
              commit: true

            ignore:
              commit: false
            """
        )
        XCTAssertFalse(settings.commitIgnoreFiles)
    }

    func testReadReturnsNilWhenConfigMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ignore-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(OffsendProjectIgnoreSettings.read(directoryURL: directory))
    }

    func testReadParsesConfigAtDirectoryRoot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ignore-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try """
        version: 1

        ignore:
          commit: false
          patterns:
            - ".env*"
        """.write(
            to: directory.appendingPathComponent(".offsend.yml"),
            atomically: true,
            encoding: .utf8
        )

        let settings = OffsendProjectIgnoreSettings.read(directoryURL: directory)
        XCTAssertNotNil(settings)
        XCTAssertFalse(settings?.commitIgnoreFiles ?? true)
    }

    func testIsMaterializedByIgnoreSyncMatchesSyncTargets() {
        let byID = Dictionary(
            uniqueKeysWithValues: AIWorkspacePrivacyRule.defaultRules.map { ($0.id, $0) }
        )
        // Ignore files with sensitive-pattern coverage are materialized.
        XCTAssertTrue(byID["cursor-ignore"]?.isMaterializedByIgnoreSync ?? false)
        XCTAssertTrue(byID["claude-ignore"]?.isMaterializedByIgnoreSync ?? false)
        XCTAssertTrue(byID["cursor-indexing-ignore"]?.isMaterializedByIgnoreSync ?? false)
        // Managed editor rule files (keepManagedContent) are materialized.
        XCTAssertTrue(byID["cursor-project-rules"]?.isMaterializedByIgnoreSync ?? false)
        // Context files without a sync fix are not.
        XCTAssertFalse(byID["agents-md"]?.isMaterializedByIgnoreSync ?? true)
        XCTAssertFalse(byID["git-ignore"]?.isMaterializedByIgnoreSync ?? true)
    }
}
