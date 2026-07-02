import Foundation

public struct WatchedDirectory: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Display name; defaults to the root folder name when nil.
    public var displayName: String?
    /// Bookmark that tracks the directory across moves/renames (see `WatchedDirectoryBookmark`).
    public var bookmarkData: Data
    /// Cached path for UI; updated on bookmark resolve (may be stale).
    public var resolvedPath: String?
    public var addedAt: Date
    public var lastAuditAt: Date?
    /// Raw `AIWorkspacePrivacyAuditStatus` value: `pass`, `warning`, or `fail`.
    public var lastStatus: String?

    public init(
        id: UUID = UUID(),
        displayName: String? = nil,
        bookmarkData: Data,
        resolvedPath: String? = nil,
        addedAt: Date = Date(),
        lastAuditAt: Date? = nil,
        lastStatus: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.resolvedPath = resolvedPath
        self.addedAt = addedAt
        self.lastAuditAt = lastAuditAt
        self.lastStatus = lastStatus
    }
}

public enum WatchedDirectoryPathMatcher {
    public static func standardizedPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    public static func matches(_ url: URL, entry: WatchedDirectory) -> Bool {
        let target = standardizedPath(for: url)
        if let resolved = entry.resolvedPath {
            return standardizedPath(for: URL(fileURLWithPath: resolved)) == target
        }
        return false
    }

    public static func firstIndex(in entries: [WatchedDirectory], matching url: URL) -> Int? {
        entries.firstIndex { matches(url, entry: $0) }
    }
}

public struct WatchedDirectoryBookmarkResolution: Sendable {
    public let url: URL
    public let bookmarkWasStale: Bool

    public init(url: URL, bookmarkWasStale: Bool) {
        self.url = url
        self.bookmarkWasStale = bookmarkWasStale
    }
}

/// Bookmarks track user-selected directories across moves/renames. The app is not sandboxed,
/// so security-scoped access (`start/stopAccessingSecurityScopedResource`) is intentionally not used;
/// `.withSecurityScope` is kept only so bookmark data persisted by earlier builds keeps resolving.
public enum WatchedDirectoryBookmark {
    public enum Error: Swift.Error {
        case accessDenied
    }

    public static func make(from url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public static func resolve(_ data: Data) throws -> WatchedDirectoryBookmarkResolution {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return WatchedDirectoryBookmarkResolution(url: url, bookmarkWasStale: isStale)
    }

    public static func refreshBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

public enum DirectoryWatchLimits {
    public static let freeMaxRoots = 1

    /// `nil` means unlimited (Pro).
    public static func maxRoots(workspaceAuditFull: Bool) -> Int? {
        workspaceAuditFull ? nil : freeMaxRoots
    }

    public static func canAddMore(currentCount: Int, workspaceAuditFull: Bool) -> Bool {
        guard let limit = maxRoots(workspaceAuditFull: workspaceAuditFull) else { return true }
        return currentCount < limit
    }

    /// Oldest entries first; callers use prefix for active watch slots on limited tiers.
    public static func activeEntries(
        from entries: [WatchedDirectory],
        workspaceAuditFull: Bool
    ) -> [WatchedDirectory] {
        let sorted = entries.sorted { $0.addedAt < $1.addedAt }
        guard let limit = maxRoots(workspaceAuditFull: workspaceAuditFull) else { return sorted }
        return Array(sorted.prefix(limit))
    }
}

public enum DirectoryWatchAuditThrottle {
    /// Coalesce bursts of file-system events before requesting an audit.
    public static let debounceInterval: TimeInterval = 2
    /// Minimum spacing between automatic re-audits of the same watched directory.
    public static let minAuditInterval: TimeInterval = 30
    /// Latency passed to `FSEventStreamCreate` (seconds).
    public static let fsEventsLatency: TimeInterval = 0.5

    /// Whether a watch audit should run now. `force` bypasses the throttle (e.g. user actions,
    /// initial audits); otherwise an audit is skipped when the previous one ran too recently.
    public static func shouldRunAudit(
        lastAuditAt: Date?,
        now: Date = Date(),
        force: Bool,
        minInterval: TimeInterval = minAuditInterval
    ) -> Bool {
        if force { return true }
        guard let lastAuditAt else { return true }
        return now.timeIntervalSince(lastAuditAt) >= minInterval
    }
}
