import Foundation
import XCTest
@testable import StorageCore

final class DirectoryWatchSettingsSnapshotTests: XCTestCase {
    private func snapshot(
        _ mutate: (inout AppSettings) -> Void = { _ in },
        workspaceAuditFull: Bool = false
    ) -> DirectoryWatchSettingsSnapshot {
        var settings = AppSettings.default
        mutate(&settings)
        return DirectoryWatchSettingsSnapshot(settings: settings, workspaceAuditFull: workspaceAuditFull)
    }

    private func directory(_ id: UUID = UUID(), bookmark: [UInt8] = [0x01]) -> WatchedDirectory {
        WatchedDirectory(id: id, bookmarkData: Data(bookmark))
    }

    func testIdenticalSettingsProduceEqualFingerprints() {
        let dir = directory()
        let a = snapshot { $0.directoryWatchEnabled = true; $0.watchedDirectories = [dir] }
        let b = snapshot { $0.directoryWatchEnabled = true; $0.watchedDirectories = [dir] }

        XCTAssertEqual(a.streamsFingerprint, b.streamsFingerprint)
        XCTAssertEqual(a.auditConfigurationFingerprint, b.auditConfigurationFingerprint)
    }

    func testTogglingEnabledChangesOnlyStreamsFingerprint() {
        let dir = directory()
        let off = snapshot { $0.directoryWatchEnabled = false; $0.watchedDirectories = [dir] }
        let on = snapshot { $0.directoryWatchEnabled = true; $0.watchedDirectories = [dir] }

        XCTAssertNotEqual(off.streamsFingerprint, on.streamsFingerprint)
        XCTAssertEqual(off.auditConfigurationFingerprint, on.auditConfigurationFingerprint)
    }

    func testAddingWatchedDirectoryChangesStreamsFingerprint() {
        let base = snapshot { $0.directoryWatchEnabled = true; $0.watchedDirectories = [self.directory()] }
        let extended = snapshot {
            $0.directoryWatchEnabled = true
            $0.watchedDirectories = [self.directory(), self.directory()]
        }

        XCTAssertNotEqual(base.streamsFingerprint, extended.streamsFingerprint)
    }

    func testConfigurationChangesAffectOnlyAuditFingerprint() {
        let dir = directory()
        let base = snapshot({ $0.directoryWatchEnabled = true; $0.watchedDirectories = [dir] }, workspaceAuditFull: false)

        let tariffChanged = snapshot({ $0.directoryWatchEnabled = true; $0.watchedDirectories = [dir] }, workspaceAuditFull: true)
        XCTAssertEqual(base.streamsFingerprint, tariffChanged.streamsFingerprint)
        XCTAssertNotEqual(base.auditConfigurationFingerprint, tariffChanged.auditConfigurationFingerprint)

        let disabledRules = snapshot {
            $0.directoryWatchEnabled = true
            $0.watchedDirectories = [dir]
            $0.directoryCheckDisabledRuleIDs = ["copilot-exclude"]
        }
        XCTAssertEqual(base.streamsFingerprint, disabledRules.streamsFingerprint)
        XCTAssertNotEqual(base.auditConfigurationFingerprint, disabledRules.auditConfigurationFingerprint)

        let skipped = snapshot {
            $0.directoryWatchEnabled = true
            $0.watchedDirectories = [dir]
            $0.directoryCheckExtraSkippedDirectories = ["vendor"]
        }
        XCTAssertNotEqual(base.auditConfigurationFingerprint, skipped.auditConfigurationFingerprint)

        let template = snapshot {
            $0.directoryWatchEnabled = true
            $0.watchedDirectories = [dir]
            $0.directoryCheckCustomIgnoreTemplate = "secret/"
        }
        XCTAssertNotEqual(base.auditConfigurationFingerprint, template.auditConfigurationFingerprint)
    }

    func testDisabledRuleOrderDoesNotAffectFingerprint() {
        let dir = directory()
        let a = snapshot { $0.watchedDirectories = [dir]; $0.directoryCheckDisabledRuleIDs = ["a", "b"] }
        let b = snapshot { $0.watchedDirectories = [dir]; $0.directoryCheckDisabledRuleIDs = ["b", "a"] }

        XCTAssertEqual(a.auditConfigurationFingerprint, b.auditConfigurationFingerprint)
    }

    func testNeedsStreamReload() {
        XCTAssertFalse(snapshot { $0.directoryWatchEnabled = false; $0.watchedDirectories = [] }.needsStreamReload)
        XCTAssertTrue(snapshot { $0.directoryWatchEnabled = true; $0.watchedDirectories = [] }.needsStreamReload)
        XCTAssertTrue(snapshot { $0.directoryWatchEnabled = false; $0.watchedDirectories = [self.directory()] }.needsStreamReload)
    }

    func testUpdateActionsNoChange() {
        let dir = directory()
        let snap = snapshot { $0.directoryWatchEnabled = true; $0.watchedDirectories = [dir] }

        let actions = snap.updateActions(comparedToPrevious: snap)

        XCTAssertFalse(actions.reloadStreams)
        XCTAssertFalse(actions.reauditActiveDirectories)
    }

    func testUpdateActionsStreamChangeReloadsStreams() {
        let dir = directory()
        let previous = snapshot { $0.directoryWatchEnabled = false; $0.watchedDirectories = [dir] }
        let current = snapshot { $0.directoryWatchEnabled = true; $0.watchedDirectories = [dir] }

        let actions = current.updateActions(comparedToPrevious: previous)

        XCTAssertTrue(actions.reloadStreams)
        XCTAssertFalse(actions.reauditActiveDirectories)
    }

    func testUpdateActionsAddingWatchedDirectoryReloadsStreamsWhenComparedToAppliedSnapshot() {
        let first = directory(bookmark: [0x01])
        let second = directory(bookmark: [0x02])
        let applied = snapshot { $0.directoryWatchEnabled = true; $0.watchedDirectories = [first] }
        let afterAdd = snapshot { $0.directoryWatchEnabled = true; $0.watchedDirectories = [first, second] }

        let actions = afterAdd.updateActions(comparedToPrevious: applied)

        XCTAssertTrue(actions.reloadStreams)
        XCTAssertFalse(actions.reauditActiveDirectories)
    }

    /// Regression: `saveSettings` must compare against the last *applied* snapshot, not the
    /// post-mutation settings (which would always match and skip stream reload).
    func testUpdateActionsSelfComparisonDoesNotReloadStreams() {
        let dir = directory()
        let applied = snapshot { $0.directoryWatchEnabled = true; $0.watchedDirectories = [dir] }

        let buggyActions = applied.updateActions(comparedToPrevious: applied)

        XCTAssertFalse(buggyActions.reloadStreams)

        let previous = snapshot { $0.directoryWatchEnabled = false; $0.watchedDirectories = [dir] }
        let correctActions = applied.updateActions(comparedToPrevious: previous)

        XCTAssertTrue(correctActions.reloadStreams)
    }

    func testUpdateActionsConfigChangeReauditsWhenEnabledAndNonEmpty() {
        let dir = directory()
        let previous = snapshot({ $0.directoryWatchEnabled = true; $0.watchedDirectories = [dir] }, workspaceAuditFull: false)
        let current = snapshot({ $0.directoryWatchEnabled = true; $0.watchedDirectories = [dir] }, workspaceAuditFull: true)

        let actions = current.updateActions(comparedToPrevious: previous)

        XCTAssertFalse(actions.reloadStreams)
        XCTAssertTrue(actions.reauditActiveDirectories)
    }

    func testUpdateActionsConfigChangeDoesNotReauditWhenNoDirectories() {
        let previous = snapshot({ $0.directoryWatchEnabled = true; $0.watchedDirectories = [] }, workspaceAuditFull: false)
        let current = snapshot({ $0.directoryWatchEnabled = true; $0.watchedDirectories = [] }, workspaceAuditFull: true)

        let actions = current.updateActions(comparedToPrevious: previous)

        XCTAssertFalse(actions.reauditActiveDirectories)
    }
}
