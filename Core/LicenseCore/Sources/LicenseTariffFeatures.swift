import Foundation

/// Keys in `LicensePricingPlan.features` from `/pricing` (and future license payloads).
public enum LicenseTariffFeatureKey: String, CaseIterable, Sendable {
    case safePasteUnlimited = "safe_paste_unlimited"
    case advancedDetectors = "advanced_detectors"
    case customDictionaries = "custom_dictionaries"
    case workspaceAuditFull = "workspace_audit_full"
    case workspaceAuditAutofix = "workspace_audit_autofix"
}

/// Resolved booleans for in-app gating (settings, optional runtime checks).
public struct LicenseTariffFeatures: Equatable, Sendable {
    public var safePasteUnlimited: Bool
    public var advancedDetectors: Bool
    public var customDictionaries: Bool
    public var workspaceAuditFull: Bool
    public var workspaceAuditAutofix: Bool

    public static let freeTier = Self(
        safePasteUnlimited: false,
        advancedDetectors: false,
        // Custom dictionaries are available to every user, regardless of plan.
        customDictionaries: true,
        workspaceAuditFull: false,
        workspaceAuditAutofix: false
    )

    /// When Pro is active but the catalog has no per-feature map (nil/empty), treat as full access.
    public static let proWithoutFeatureMap = Self(
        safePasteUnlimited: true,
        advancedDetectors: true,
        customDictionaries: true,
        workspaceAuditFull: true,
        workspaceAuditAutofix: true
    )

    public init(
        safePasteUnlimited: Bool,
        advancedDetectors: Bool,
        customDictionaries: Bool,
        workspaceAuditFull: Bool,
        workspaceAuditAutofix: Bool
    ) {
        self.safePasteUnlimited = safePasteUnlimited
        self.advancedDetectors = advancedDetectors
        self.customDictionaries = customDictionaries
        self.workspaceAuditFull = workspaceAuditFull
        self.workspaceAuditAutofix = workspaceAuditAutofix
    }

    public init(features: [String: Bool]) {
        self.safePasteUnlimited = Self.bool(for: .safePasteUnlimited, in: features)
        self.advancedDetectors = Self.bool(for: .advancedDetectors, in: features)
        // Custom dictionaries are available to every user, regardless of plan.
        self.customDictionaries = true
        self.workspaceAuditFull = Self.workspaceAuditFullEnabled(in: features)
        self.workspaceAuditAutofix = Self.workspaceAuditAutofixEnabled(in: features)
    }

    private static func bool(for key: LicenseTariffFeatureKey, in features: [String: Bool]) -> Bool {
        features[key.rawValue] == true
    }

    /// `/pricing` may expose legacy keys (e.g. `folder_scan`) instead of in-app feature ids.
    private static func workspaceAuditFullEnabled(in features: [String: Bool]) -> Bool {
        bool(for: .workspaceAuditFull, in: features) || features["folder_scan"] == true
    }

    private static func workspaceAuditAutofixEnabled(in features: [String: Bool]) -> Bool {
        if bool(for: .workspaceAuditAutofix, in: features) { return true }
        if features[LicenseTariffFeatureKey.workspaceAuditAutofix.rawValue] == false { return false }
        return features["folder_scan"] == true
    }
}

public enum LicenseTariffFeaturesResolver: Sendable {
    /// Resolves feature flags for UI gating. Free tier never reads the pricing map; Pro uses the best-matching catalog plan.
    public static func resolve(isPro: Bool, pricing: LicensePricingPresentation) -> LicenseTariffFeatures {
        guard isPro else { return .freeTier }
        guard let plan = resolveCatalogPlan(pricing: pricing) else {
            return .proWithoutFeatureMap
        }
        guard let raw = plan.features, !raw.isEmpty else {
            return .proWithoutFeatureMap
        }
        return LicenseTariffFeatures(features: raw)
    }

    private static func resolveCatalogPlan(pricing: LicensePricingPresentation) -> LicensePricingPlan? {
        if let byDefault = pricing.plans.first(where: { $0.planId == pricing.defaultCheckoutPlanId }) {
            return byDefault
        }
        if let marked = pricing.plans.first(where: { $0.isDefault == true }) {
            return marked
        }
        return pricing.plans.first
    }
}
