import Foundation

/// A watched directory that currently needs attention, shaped for menu-bar display.
public struct WorkspaceStatusMenuEntry: Equatable, Identifiable {
    public var id: UUID { watchID }
    public let watchID: UUID
    public let path: String
    public let displayName: String
    public let status: AIWorkspacePrivacyAuditStatus

    public init(
        watchID: UUID,
        path: String,
        displayName: String,
        status: AIWorkspacePrivacyAuditStatus
    ) {
        self.watchID = watchID
        self.path = path
        self.displayName = displayName
        self.status = status
    }

    /// Minimal description of a watched directory needed to build a menu entry.
    public struct Source: Equatable {
        public let watchID: UUID
        public let resolvedPath: String?
        public let displayName: String?

        public init(watchID: UUID, resolvedPath: String?, displayName: String?) {
            self.watchID = watchID
            self.resolvedPath = resolvedPath
            self.displayName = displayName
        }
    }

    /// Builds FAIL entries for active watched directories, sorted alphabetically by display name.
    public static func attentionEntries(
        from sources: [Source],
        statusByWatchID: [UUID: AIWorkspacePrivacyAuditStatus],
        activeWatchIDs: Set<UUID>
    ) -> [WorkspaceStatusMenuEntry] {
        sources
            .filter { activeWatchIDs.contains($0.watchID) }
            .compactMap { source -> WorkspaceStatusMenuEntry? in
                guard let status = statusByWatchID[source.watchID],
                      WorkspaceWatchStatusDegrade.countsAsAttention(status) else {
                    return nil
                }
                let path = source.resolvedPath ?? source.displayName ?? source.watchID.uuidString
                let displayName = source.displayName ?? URL(fileURLWithPath: path).lastPathComponent
                return WorkspaceStatusMenuEntry(
                    watchID: source.watchID,
                    path: path,
                    displayName: displayName,
                    status: status
                )
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }
}
