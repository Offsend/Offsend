import Foundation
import XCTest
@testable import StorageCore

final class WatchedDirectoryBookmarkTests: XCTestCase {
    func testBookmarkRoundtripPreservesPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let bookmark = try WatchedDirectoryBookmark.make(from: directory)
        let resolution = try WatchedDirectoryBookmark.resolve(bookmark)

        XCTAssertEqual(
            WatchedDirectoryPathMatcher.standardizedPath(for: resolution.url),
            WatchedDirectoryPathMatcher.standardizedPath(for: directory)
        )

        resolution.url.stopAccessingSecurityScopedResource()
    }

    func testPathMatcherTreatsSymlinkTargetsAsSameDirectory() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-watch-base-\(UUID().uuidString)", isDirectory: true)
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-watch-link-\(UUID().uuidString)", isDirectory: false)

        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: base)

        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: base)
        }

        let entry = WatchedDirectory(
            bookmarkData: Data(),
            resolvedPath: WatchedDirectoryPathMatcher.standardizedPath(for: base)
        )

        XCTAssertTrue(WatchedDirectoryPathMatcher.matches(link, entry: entry))
    }
}

final class DirectoryWatchLimitsTests: XCTestCase {
    func testActiveEntriesRespectFreeLimit() {
        let entries = [
            WatchedDirectory(bookmarkData: Data(), addedAt: Date(timeIntervalSince1970: 1)),
            WatchedDirectory(bookmarkData: Data(), addedAt: Date(timeIntervalSince1970: 2))
        ]

        let active = DirectoryWatchLimits.activeEntries(from: entries, workspaceAuditFull: false)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].addedAt, entries[0].addedAt)
    }

    func testActiveEntriesAllowUnlimitedOnPro() {
        let entries = (0..<12).map {
            WatchedDirectory(bookmarkData: Data(), addedAt: Date(timeIntervalSince1970: TimeInterval($0)))
        }

        let active = DirectoryWatchLimits.activeEntries(from: entries, workspaceAuditFull: true)
        XCTAssertEqual(active.count, 12)
    }

    func testActiveEntriesSortByAddedAtRegardlessOfInputOrder() {
        let older = WatchedDirectory(bookmarkData: Data(), addedAt: Date(timeIntervalSince1970: 1))
        let newer = WatchedDirectory(bookmarkData: Data(), addedAt: Date(timeIntervalSince1970: 2))

        let active = DirectoryWatchLimits.activeEntries(from: [newer, older], workspaceAuditFull: false)

        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].id, older.id, "The oldest directory keeps the single Free slot regardless of array order.")
    }

    func testActiveEntriesReturnAllWhenUnderLimit() {
        let entries = (0..<3).map {
            WatchedDirectory(bookmarkData: Data(), addedAt: Date(timeIntervalSince1970: TimeInterval($0)))
        }

        let active = DirectoryWatchLimits.activeEntries(from: entries, workspaceAuditFull: true)
        XCTAssertEqual(active.count, 3)
    }

    func testCanAddMoreRespectsTierLimits() {
        XCTAssertTrue(DirectoryWatchLimits.canAddMore(currentCount: 0, workspaceAuditFull: false))
        XCTAssertFalse(DirectoryWatchLimits.canAddMore(currentCount: 1, workspaceAuditFull: false))
        XCTAssertTrue(DirectoryWatchLimits.canAddMore(currentCount: 100, workspaceAuditFull: true))
    }
}

final class DirectoryWatchAuditThrottleTests: XCTestCase {
    func testForceAlwaysRuns() {
        XCTAssertTrue(
            DirectoryWatchAuditThrottle.shouldRunAudit(
                lastAuditAt: Date(timeIntervalSince1970: 100),
                now: Date(timeIntervalSince1970: 101),
                force: true
            )
        )
    }

    func testRunsWhenNeverAudited() {
        XCTAssertTrue(DirectoryWatchAuditThrottle.shouldRunAudit(lastAuditAt: nil, force: false))
    }

    func testSkipsWithinMinInterval() {
        XCTAssertFalse(
            DirectoryWatchAuditThrottle.shouldRunAudit(
                lastAuditAt: Date(timeIntervalSince1970: 100),
                now: Date(timeIntervalSince1970: 129),
                force: false
            )
        )
    }

    func testRunsAtOrAfterMinInterval() {
        XCTAssertTrue(
            DirectoryWatchAuditThrottle.shouldRunAudit(
                lastAuditAt: Date(timeIntervalSince1970: 100),
                now: Date(timeIntervalSince1970: 130),
                force: false
            )
        )
    }
}

final class AppSettingsDirectoryWatchMigrationTests: XCTestCase {
    func testDecodesLegacySettingsWithoutWatchFields() throws {
        let json = """
        {
          "hasCompletedOnboarding": false,
          "protectionEnabled": true,
          "clipboardMonitoringEnabled": true,
          "launchAtLogin": false,
          "defaultNoRiskAction": "pasteOriginal",
          "enabledDetectors": ["email"],
          "mappingTTL": "oneHour",
          "restoreBehavior": "copyToClipboard",
          "preserveOriginalClipboard": true,
          "analyticsOptIn": false,
          "allowPasteOriginalForCriticalSecrets": false,
          "excludedClipboardApplications": [],
          "directoryCheckDisabledRuleIDs": [],
          "directoryCheckConfirmFix": true,
          "directoryCheckExtraSkippedDirectories": []
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(settings.directoryWatchEnabled)
        XCTAssertTrue(settings.watchedDirectories.isEmpty)
        XCTAssertTrue(settings.directoryWatchNotifyOnDegrade)
    }

    func testRoundTripPreservesWatchFields() throws {
        var settings = AppSettings.default
        settings.directoryWatchEnabled = true
        settings.directoryWatchNotifyOnDegrade = false
        settings.watchedDirectories = [
            WatchedDirectory(
                displayName: "project",
                bookmarkData: Data([0x01, 0x02, 0x03]),
                resolvedPath: "/tmp/project",
                addedAt: Date(timeIntervalSince1970: 1000),
                lastAuditAt: Date(timeIntervalSince1970: 2000),
                lastStatus: "warning"
            )
        ]

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded, settings)
    }
}
