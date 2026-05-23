import DetectionCore
import Foundation

/// Product analytics events — no clipboard, prompt, or entity content.
public enum AnalyticsEvent: Equatable, Sendable {
    case onboardingCompleted
    case safePasteUsed(riskLevel: RiskLevel?, entityCount: Int, usedCachedScan: Bool)
    case maskApplied
    case restoreUsed
    case pasteOriginalChosen(riskLevel: RiskLevel?)

    public var name: String {
        switch self {
        case .onboardingCompleted: "onboarding_completed"
        case .safePasteUsed: "safe_paste"
        case .maskApplied: "mask_applied"
        case .restoreUsed: "restore_used"
        case .pasteOriginalChosen: "paste_original"
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
