import DetectionCore
import Foundation

/// Product analytics events — no clipboard, prompt, or entity content.
public enum AnalyticsEvent: Equatable, Sendable {
    case onboardingCompleted
    case safePasteUsed(riskLevel: RiskLevel?, entityCount: Int, usedCachedScan: Bool)
    case maskApplied
    case restoreUsed
    case pasteOriginalChosen(riskLevel: RiskLevel?)
    case watchEnabled
    case watchDirectoryAdded(source: String)
    case watchDirectoryRemoved
    case watchStatusDegraded(fromStatus: String, toStatus: String)
    case watchNotificationOpened(action: String)
    case watchUpgradeFromLimit(source: String)
    case directoryCheckOpened(source: String)
    case checkoutStarted(source: String)

    public var name: String {
        switch self {
        case .onboardingCompleted: "onboarding_completed"
        case .safePasteUsed: "safe_paste"
        case .maskApplied: "mask_applied"
        case .restoreUsed: "restore_used"
        case .pasteOriginalChosen: "paste_original"
        case .watchEnabled: "watch_enabled"
        case .watchDirectoryAdded: "watch_directory_added"
        case .watchDirectoryRemoved: "watch_directory_removed"
        case .watchStatusDegraded: "watch_status_degraded"
        case .watchNotificationOpened: "watch_notification_opened"
        case .watchUpgradeFromLimit: "watch_upgrade_from_limit"
        case .directoryCheckOpened: "directory_check_opened"
        case .checkoutStarted: "checkout_started"
        }
    }

    public var riskLevel: RiskLevel? {
        switch self {
        case let .safePasteUsed(riskLevel, _, _): riskLevel
        case let .pasteOriginalChosen(riskLevel): riskLevel
        default: nil
        }
    }

    /// Metadata stored locally and sent to TelemetryDeck (plus `risk_level` when applicable).
    public var metadata: [String: String] {
        switch self {
        case let .safePasteUsed(_, entityCount, usedCachedScan):
            [
                "entity_count": String(entityCount),
                "used_cached_scan": usedCachedScan ? "true" : "false",
            ]
        case let .watchDirectoryAdded(source):
            ["source": source]
        case let .watchStatusDegraded(fromStatus, toStatus):
            ["from_status": fromStatus, "to_status": toStatus]
        case let .watchNotificationOpened(action):
            ["action": action]
        case let .watchUpgradeFromLimit(source),
             let .directoryCheckOpened(source),
             let .checkoutStarted(source):
            ["source": source]
        default:
            [:]
        }
    }

    public var telemetryParameters: [String: String] {
        var parameters = metadata
        switch self {
        case .safePasteUsed, .pasteOriginalChosen:
            parameters["risk_level"] = riskLevel?.rawValue ?? "none"
        default:
            break
        }
        return parameters
    }
}
