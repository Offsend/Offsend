import Foundation

public struct HookedRepository: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String?
    /// Bookmark that tracks the git repository root across moves/renames (see `WatchedDirectoryBookmark`).
    public var bookmarkData: Data
    /// Cached path for UI; updated on bookmark resolve (may be stale).
    public var resolvedPath: String?
    public var addedAt: Date
    /// `pre-commit` for now.
    public var hookType: String
    /// `block`, `warn`, or `none`.
    public var failPolicy: String
    public var includePolicyCheck: Bool
    public var installedAt: Date?
    /// `installed`, `missing`, `modified`, or `unavailable`.
    public var hookStatus: String?

    public init(
        id: UUID = UUID(),
        displayName: String? = nil,
        bookmarkData: Data,
        resolvedPath: String? = nil,
        addedAt: Date = Date(),
        hookType: String = "pre-commit",
        failPolicy: String = "block",
        includePolicyCheck: Bool = false,
        installedAt: Date? = nil,
        hookStatus: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.resolvedPath = resolvedPath
        self.addedAt = addedAt
        self.hookType = hookType
        self.failPolicy = failPolicy
        self.includePolicyCheck = includePolicyCheck
        self.installedAt = installedAt
        self.hookStatus = hookStatus
    }
}

public enum HookedRepositoryPathMatcher {
    public static func matches(_ url: URL, entry: HookedRepository) -> Bool {
        let target = WatchedDirectoryPathMatcher.standardizedPath(for: url)
        if let resolved = entry.resolvedPath {
            return WatchedDirectoryPathMatcher.standardizedPath(for: URL(fileURLWithPath: resolved)) == target
        }
        return false
    }

    public static func firstIndex(in entries: [HookedRepository], matching url: URL) -> Int? {
        entries.firstIndex { matches(url, entry: $0) }
    }
}
