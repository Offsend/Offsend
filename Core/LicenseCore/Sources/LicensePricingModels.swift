import Foundation

// MARK: - API (GET /pricing)

public struct LicensePricingPlan: Codable, Equatable, Sendable, Identifiable {
    public var planId: String
    public var name: String
    public var description: String?
    public var billingInterval: String?
    public var priceMinor: Int?
    public var priceDisplay: String?
    public var trialDays: Int?
    public var deviceLimit: Int?
    public var isDefault: Bool?
    public var ctaLabel: String?
    public var features: [String: Bool]?

    public var id: String { planId }

    public init(
        planId: String,
        name: String,
        description: String?,
        billingInterval: String?,
        priceMinor: Int?,
        priceDisplay: String?,
        trialDays: Int?,
        deviceLimit: Int?,
        isDefault: Bool?,
        ctaLabel: String?,
        features: [String: Bool]?
    ) {
        self.planId = planId
        self.name = name
        self.description = description
        self.billingInterval = billingInterval
        self.priceMinor = priceMinor
        self.priceDisplay = priceDisplay
        self.trialDays = trialDays
        self.deviceLimit = deviceLimit
        self.isDefault = isDefault
        self.ctaLabel = ctaLabel
        self.features = features
    }

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case name
        case description
        case billingInterval = "billing_interval"
        case priceMinor = "price_minor"
        case priceDisplay = "price_display"
        case trialDays = "trial_days"
        case deviceLimit = "device_limit"
        case isDefault = "is_default"
        case ctaLabel = "cta_label"
        case features
    }
}

public struct LicensePricingUI: Codable, Equatable, Sendable {
    public var headline: String?
    public var subheadline: String?
    public var restoreLabel: String?

    public init(headline: String? = nil, subheadline: String? = nil, restoreLabel: String? = nil) {
        self.headline = headline
        self.subheadline = subheadline
        self.restoreLabel = restoreLabel
    }

    enum CodingKeys: String, CodingKey {
        case headline
        case subheadline
        case restoreLabel = "restore_label"
    }
}

public struct LicensePricingCatalog: Codable, Equatable, Sendable {
    public var status: String
    public var currency: String?
    public var plans: [LicensePricingPlan]
    public var ui: LicensePricingUI?
    public var cacheTtlSeconds: Int?

    public init(
        status: String,
        currency: String? = nil,
        plans: [LicensePricingPlan],
        ui: LicensePricingUI? = nil,
        cacheTtlSeconds: Int? = nil
    ) {
        self.status = status
        self.currency = currency
        self.plans = plans
        self.ui = ui
        self.cacheTtlSeconds = cacheTtlSeconds
    }

    enum CodingKeys: String, CodingKey {
        case status
        case currency
        case plans
        case ui
        case cacheTtlSeconds = "cache_ttl_seconds"
    }
}

// MARK: - Presentation

public struct LicensePricingFallbackStrings: Equatable, Sendable {
    public var headline: String
    public var subheadline: String
    public var buyButtonTitle: String

    public init(headline: String, subheadline: String, buyButtonTitle: String) {
        self.headline = headline
        self.subheadline = subheadline
        self.buyButtonTitle = buyButtonTitle
    }
}

public struct LicensePricingPresentation: Equatable, Sendable {
    /// When false, do not show `primaryPriceDisplay` (stale pricing risk).
    public var showsPrice: Bool
    public var headline: String
    public var subheadline: String
    public var buyButtonTitle: String
    public var defaultCheckoutPlanId: String
    public var primaryPriceDisplay: String?
    /// Plan card title (e.g. "Offsend Pro").
    public var productDisplayName: String
    public var plans: [LicensePricingPlan]
    public var restoreGroupTitle: String?
    public var restoreGroupSubtitle: String?
    public var defaultPlanDescription: String?
    public var defaultPlanDeviceLimit: Int?
    public var featureBulletLabels: [String]

    public init(
        showsPrice: Bool,
        headline: String,
        subheadline: String,
        buyButtonTitle: String,
        defaultCheckoutPlanId: String,
        primaryPriceDisplay: String?,
        productDisplayName: String,
        plans: [LicensePricingPlan],
        restoreGroupTitle: String?,
        restoreGroupSubtitle: String?,
        defaultPlanDescription: String?,
        defaultPlanDeviceLimit: Int?,
        featureBulletLabels: [String]
    ) {
        self.showsPrice = showsPrice
        self.headline = headline
        self.subheadline = subheadline
        self.buyButtonTitle = buyButtonTitle
        self.defaultCheckoutPlanId = defaultCheckoutPlanId
        self.primaryPriceDisplay = primaryPriceDisplay
        self.productDisplayName = productDisplayName
        self.plans = plans
        self.restoreGroupTitle = restoreGroupTitle
        self.restoreGroupSubtitle = restoreGroupSubtitle
        self.defaultPlanDescription = defaultPlanDescription
        self.defaultPlanDeviceLimit = defaultPlanDeviceLimit
        self.featureBulletLabels = featureBulletLabels
    }

    public static func fallback(_ strings: LicensePricingFallbackStrings, defaultPlanId: String) -> LicensePricingPresentation {
        LicensePricingPresentation(
            showsPrice: false,
            headline: strings.headline,
            subheadline: strings.subheadline,
            buyButtonTitle: strings.buyButtonTitle,
            defaultCheckoutPlanId: defaultPlanId,
            primaryPriceDisplay: nil,
            productDisplayName: strings.headline,
            plans: [],
            restoreGroupTitle: nil,
            restoreGroupSubtitle: nil,
            defaultPlanDescription: nil,
            defaultPlanDeviceLimit: nil,
            featureBulletLabels: []
        )
    }

    public static func fromCatalog(_ catalog: LicensePricingCatalog, defaultPlanIdFallback: String) -> LicensePricingPresentation {
        let defaultPlan = catalog.plans.first(where: { $0.isDefault == true }) ?? catalog.plans.first
        let planId = defaultPlan?.planId ?? defaultPlanIdFallback
        let buyTitle = defaultPlan?.ctaLabel ?? "Buy Pro"
        let headline = catalog.ui?.headline ?? defaultPlan?.name ?? "Offsend Pro"
        let sub = catalog.ui?.subheadline ?? defaultPlan?.description ?? ""
        let priceLine = defaultPlan?.priceDisplay
        let bullets = Self.featureBullets(from: defaultPlan?.features)
        let productName = defaultPlan?.name ?? headline

        return LicensePricingPresentation(
            showsPrice: true,
            headline: headline,
            subheadline: sub,
            buyButtonTitle: buyTitle,
            defaultCheckoutPlanId: planId,
            primaryPriceDisplay: priceLine,
            productDisplayName: productName,
            plans: catalog.plans,
            restoreGroupTitle: catalog.ui?.restoreLabel,
            restoreGroupSubtitle: nil,
            defaultPlanDescription: defaultPlan?.description,
            defaultPlanDeviceLimit: defaultPlan?.deviceLimit,
            featureBulletLabels: bullets
        )
    }

    private static func featureBullets(from features: [String: Bool]?) -> [String] {
        guard let features else { return [] }
        return features.filter(\.value).keys.sorted().map { prettyFeatureKey($0) }
    }

    private static func prettyFeatureKey(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
