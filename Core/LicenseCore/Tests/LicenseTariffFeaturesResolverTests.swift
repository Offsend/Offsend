import Foundation
import XCTest

import LicenseCore

final class LicenseTariffFeaturesResolverTests: XCTestCase {
    private func presentation(
        defaultCheckoutPlanId: String = "pro_annual",
        plans: [LicensePricingPlan]
    ) -> LicensePricingPresentation {
        LicensePricingPresentation(
            showsPrice: true,
            headline: "H",
            subheadline: "S",
            buyButtonTitle: "Buy",
            defaultCheckoutPlanId: defaultCheckoutPlanId,
            primaryPriceDisplay: nil,
            productDisplayName: "Pro",
            plans: plans,
            restoreGroupTitle: nil,
            restoreGroupSubtitle: nil,
            defaultPlanDescription: nil,
            defaultPlanDeviceLimit: nil,
            featureBulletLabels: []
        )
    }

    func testFreeIgnoresCatalogAndIsAllDenied() {
        let plan = LicensePricingPlan(
            planId: "pro_annual",
            name: "Pro",
            description: nil,
            billingInterval: nil,
            priceMinor: nil,
            priceDisplay: nil,
            trialDays: nil,
            deviceLimit: nil,
            isDefault: true,
            ctaLabel: nil,
            features: [
                LicenseTariffFeatureKey.safePasteUnlimited.rawValue: true,
                LicenseTariffFeatureKey.advancedDetectors.rawValue: true,
                LicenseTariffFeatureKey.customDictionaries.rawValue: true,
            ]
        )
        let pricing = presentation(plans: [plan])
        let f = LicenseTariffFeaturesResolver.resolve(isPro: false, pricing: pricing)
        XCTAssertEqual(f, .freeTier)
    }

    func testProMatchesDefaultCheckoutPlanId() {
        let proPlan = LicensePricingPlan(
            planId: "pro_annual",
            name: "Annual",
            description: nil,
            billingInterval: nil,
            priceMinor: nil,
            priceDisplay: nil,
            trialDays: nil,
            deviceLimit: nil,
            isDefault: false,
            ctaLabel: nil,
            features: [
                LicenseTariffFeatureKey.safePasteUnlimited.rawValue: true,
                LicenseTariffFeatureKey.advancedDetectors.rawValue: false,
                LicenseTariffFeatureKey.customDictionaries.rawValue: true,
            ]
        )
        let other = LicensePricingPlan(
            planId: "pro_monthly",
            name: "Monthly",
            description: nil,
            billingInterval: nil,
            priceMinor: nil,
            priceDisplay: nil,
            trialDays: nil,
            deviceLimit: nil,
            isDefault: true,
            ctaLabel: nil,
            features: [
                LicenseTariffFeatureKey.safePasteUnlimited.rawValue: false,
                LicenseTariffFeatureKey.advancedDetectors.rawValue: false,
                LicenseTariffFeatureKey.customDictionaries.rawValue: false,
            ]
        )
        let pricing = presentation(defaultCheckoutPlanId: "pro_annual", plans: [other, proPlan])
        let f = LicenseTariffFeaturesResolver.resolve(isPro: true, pricing: pricing)
        XCTAssertTrue(f.safePasteUnlimited)
        XCTAssertFalse(f.advancedDetectors)
        XCTAssertTrue(f.customDictionaries)
    }

    func testProEmptyFeatureMapMeansAllEnabled() {
        let plan = LicensePricingPlan(
            planId: "pro_annual",
            name: "Pro",
            description: nil,
            billingInterval: nil,
            priceMinor: nil,
            priceDisplay: nil,
            trialDays: nil,
            deviceLimit: nil,
            isDefault: true,
            ctaLabel: nil,
            features: nil
        )
        let pricing = presentation(plans: [plan])
        let f = LicenseTariffFeaturesResolver.resolve(isPro: true, pricing: pricing)
        XCTAssertEqual(f, .proWithoutFeatureMap)
    }

    func testProNoPlansMeansAllEnabled() {
        let pricing = presentation(plans: [])
        let f = LicenseTariffFeaturesResolver.resolve(isPro: true, pricing: pricing)
        XCTAssertEqual(f, .proWithoutFeatureMap)
    }
}
