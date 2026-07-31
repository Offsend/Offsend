import XCTest
@testable import WorkspacePolicyCore

final class WorkspaceStatusMenuEntryTests: XCTestCase {
    private func source(_ id: UUID, path: String? = nil, name: String? = nil) -> WorkspaceStatusMenuEntry.Source {
        WorkspaceStatusMenuEntry.Source(watchID: id, resolvedPath: path, displayName: name)
    }

    func testExcludesWarning() {
        let warn = UUID()
        let fail = UUID()
        let sources = [source(warn, name: "warn"), source(fail, name: "fail")]

        let entries = WorkspaceStatusMenuEntry.attentionEntries(
            from: sources,
            statusByWatchID: [warn: .warning, fail: .fail],
            activeWatchIDs: [warn, fail]
        )

        XCTAssertEqual(entries.map(\.watchID), [fail])
    }

    func testExcludesPassAndUnknownStatuses() {
        let passing = UUID()
        let failing = UUID()
        let unknown = UUID()
        let sources = [
            source(passing, path: "/tmp/ok", name: "ok"),
            source(failing, path: "/tmp/bad", name: "bad"),
            source(unknown, path: "/tmp/unknown", name: "unknown")
        ]

        let entries = WorkspaceStatusMenuEntry.attentionEntries(
            from: sources,
            statusByWatchID: [passing: .pass, failing: .fail],
            activeWatchIDs: [passing, failing, unknown]
        )

        XCTAssertEqual(entries.map(\.watchID), [failing])
    }

    func testExcludesInactiveDirectories() {
        let active = UUID()
        let inactive = UUID()
        let sources = [source(active, name: "a"), source(inactive, name: "b")]

        let entries = WorkspaceStatusMenuEntry.attentionEntries(
            from: sources,
            statusByWatchID: [active: .fail, inactive: .fail],
            activeWatchIDs: [active]
        )

        XCTAssertEqual(entries.map(\.watchID), [active])
    }

    func testSortsByDisplayNameCaseInsensitively() {
        let beta = UUID()
        let alpha = UUID()
        let sources = [source(beta, name: "Beta"), source(alpha, name: "alpha")]

        let entries = WorkspaceStatusMenuEntry.attentionEntries(
            from: sources,
            statusByWatchID: [beta: .fail, alpha: .fail],
            activeWatchIDs: [beta, alpha]
        )

        XCTAssertEqual(entries.map(\.displayName), ["alpha", "Beta"])
    }

    func testDisplayNameFallsBackToLastPathComponent() {
        let id = UUID()

        let entries = WorkspaceStatusMenuEntry.attentionEntries(
            from: [source(id, path: "/Users/me/project", name: nil)],
            statusByWatchID: [id: .fail],
            activeWatchIDs: [id]
        )

        XCTAssertEqual(entries.first?.displayName, "project")
        XCTAssertEqual(entries.first?.path, "/Users/me/project")
    }

    func testPathFallsBackToWatchIDWhenNoPathOrName() {
        let id = UUID()

        let entries = WorkspaceStatusMenuEntry.attentionEntries(
            from: [source(id, path: nil, name: nil)],
            statusByWatchID: [id: .fail],
            activeWatchIDs: [id]
        )

        XCTAssertEqual(entries.first?.path, id.uuidString)
    }
}
