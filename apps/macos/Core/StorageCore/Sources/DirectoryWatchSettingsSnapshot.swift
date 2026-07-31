import Foundation

/// Snapshot of the directory-watch–relevant settings used to decide, after a settings
/// change, whether FSEvents streams must be reloaded and/or active directories re-audited.
public struct DirectoryWatchSettingsSnapshot: Equatable {
    public var directoryWatchEnabled: Bool
    public var watchedDirectories: [WatchedDirectory]
    public var disabledRuleIDs: Set<String>
    public var extraSkippedDirectories: [String]
    public var customIgnoreTemplate: String?
    public var workspaceAuditFull: Bool

    public init(settings: AppSettings, workspaceAuditFull: Bool) {
        directoryWatchEnabled = settings.directoryWatchEnabled
        watchedDirectories = settings.watchedDirectories
        disabledRuleIDs = settings.directoryCheckDisabledRuleIDs
        extraSkippedDirectories = settings.directoryCheckExtraSkippedDirectories
        customIgnoreTemplate = settings.directoryCheckCustomIgnoreTemplate
        self.workspaceAuditFull = workspaceAuditFull
    }

    public var needsStreamReload: Bool {
        directoryWatchEnabled || !watchedDirectories.isEmpty
    }

    /// Changes here require tearing down and recreating FSEvents streams.
    public var streamsFingerprint: String {
        let ids = watchedDirectories.map(\.id.uuidString).joined(separator: ",")
        let bookmarks = watchedDirectories.map { $0.bookmarkData.base64EncodedString() }.joined(separator: "|")
        return "\(directoryWatchEnabled)|\(ids)|\(bookmarks)"
    }

    /// Changes here require re-auditing active directories with the new configuration.
    public var auditConfigurationFingerprint: String {
        let skipped = extraSkippedDirectories.joined(separator: ",")
        let disabled = disabledRuleIDs.sorted().joined(separator: ",")
        let template = customIgnoreTemplate ?? ""
        return "\(workspaceAuditFull)|\(disabled)|\(skipped)|\(template)"
    }

    /// Side effects required after a settings change, comparing this (new) snapshot to a previous one.
    public struct UpdateActions: Equatable {
        public let reloadStreams: Bool
        public let reauditActiveDirectories: Bool

        public init(reloadStreams: Bool, reauditActiveDirectories: Bool) {
            self.reloadStreams = reloadStreams
            self.reauditActiveDirectories = reauditActiveDirectories
        }
    }

    public func updateActions(comparedToPrevious previous: DirectoryWatchSettingsSnapshot) -> UpdateActions {
        let reloadStreams = previous.streamsFingerprint != streamsFingerprint
        let reaudit = previous.auditConfigurationFingerprint != auditConfigurationFingerprint
            && directoryWatchEnabled
            && !watchedDirectories.isEmpty
        return UpdateActions(reloadStreams: reloadStreams, reauditActiveDirectories: reaudit)
    }
}
