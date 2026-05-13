import Foundation

/// Offline Pro gating using `expires_at` / `grace_until` from the last successful server response (see backend docs §9.3).
public enum LicenseOfflineEntitlement: Sendable {
    case proActive
    case proGrace
    case free

    public static func resolve(expiresAt: Date?, graceUntil: Date?, now: Date = Date()) -> LicenseOfflineEntitlement {
        if let exp = expiresAt, now < exp {
            return .proActive
        }
        let graceEnd = graceUntil ?? expiresAt
        if let graceEnd, now < graceEnd {
            return .proGrace
        }
        return .free
    }

    public static func isProUnlocked(expiresAt: Date?, graceUntil: Date?, now: Date = Date()) -> Bool {
        switch resolve(expiresAt: expiresAt, graceUntil: graceUntil, now: now) {
        case .proActive, .proGrace:
            return true
        case .free:
            return false
        }
    }
}
