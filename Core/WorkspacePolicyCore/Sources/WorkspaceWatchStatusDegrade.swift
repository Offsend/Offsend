import Foundation

public enum WorkspaceWatchStatusDegrade {
    public static func didDegrade(
        from previous: AIWorkspacePrivacyAuditStatus?,
        to newStatus: AIWorkspacePrivacyAuditStatus
    ) -> Bool {
        guard let previous else { return false }
        return rank(newStatus) > rank(previous)
    }

    /// Watch UI and menu bar surface only FAIL so incomplete scans / recommended gaps do not look alarming.
    public static func countsAsAttention(_ status: AIWorkspacePrivacyAuditStatus) -> Bool {
        status == .fail
    }

    /// Free tier notifies only on FAIL; Pro also notifies on WARNING.
    /// Also notifies when new sensitive paths become exposed, including while status stays at FAIL.
    public static func shouldNotify(
        from previous: AIWorkspacePrivacyAuditStatus?,
        to newStatus: AIWorkspacePrivacyAuditStatus,
        workspaceAuditFull: Bool,
        addedExposedRelativePaths: [String] = []
    ) -> Bool {
        if !addedExposedRelativePaths.isEmpty {
            if workspaceAuditFull {
                return true
            }
            if newStatus == .fail {
                return true
            }
        }

        guard didDegrade(from: previous, to: newStatus) else { return false }
        if workspaceAuditFull {
            return true
        }
        return newStatus == .fail
    }

    public static func worstStatus(in statuses: [AIWorkspacePrivacyAuditStatus]) -> AIWorkspacePrivacyAuditStatus? {
        statuses.max(by: { rank($0) < rank($1) })
    }

    private static func rank(_ status: AIWorkspacePrivacyAuditStatus) -> Int {
        switch status {
        case .pass: 0
        case .warning: 1
        case .fail: 2
        }
    }
}
