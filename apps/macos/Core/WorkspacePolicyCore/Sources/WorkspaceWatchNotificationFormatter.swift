import Foundation

public enum WorkspaceWatchNotificationFormatter {
    /// Up to `limit` newly exposed relative paths for notification copy.
    public static func exposedPathsSummary(
        from delta: AIWorkspacePrivacyAuditDelta,
        limit: Int = 2
    ) -> String? {
        pathsSummary(delta.addedExposedRelativePaths, limit: limit)
    }

    /// Up to `limit` exposed relative paths for notification copy, with a "+N more" suffix when truncated.
    public static func exposedPathsSummary(
        from result: AIWorkspacePrivacyAuditResult,
        limit: Int = 2
    ) -> String? {
        pathsSummary(result.exposedRelativePaths, limit: limit)
    }

    private static func pathsSummary(_ paths: [String], limit: Int) -> String? {
        guard !paths.isEmpty else { return nil }
        guard limit > 0 else { return nil }

        if paths.count <= limit {
            return paths.joined(separator: ", ")
        }

        let prefix = paths.prefix(limit).joined(separator: ", ")
        return "\(prefix) +\(paths.count - limit) more"
    }
}

public extension AIWorkspacePrivacyAuditResult {
    /// Alias for `allExposedRelativePaths` so notification copy and audit results use a
    /// single source of truth (pattern-level and per-tool rule exposures combined).
    var exposedRelativePaths: [String] {
        allExposedRelativePaths
    }
}
