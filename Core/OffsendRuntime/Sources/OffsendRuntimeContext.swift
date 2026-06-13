import DetectionCore
import Foundation
import LicenseCore
import StorageCore

public struct OffsendRuntimeContext: Sendable {
    public let settings: AppSettings
    public let customDictionaries: [CustomDictionaryItem]
    public let licenseState: LicenseState
    public let tariffFeatures: LicenseTariffFeatures
    public let isProEntitlementActive: Bool

    public init(
        settings: AppSettings,
        customDictionaries: [CustomDictionaryItem],
        licenseState: LicenseState
    ) {
        self.settings = settings
        self.customDictionaries = customDictionaries
        self.licenseState = licenseState
        self.isProEntitlementActive = Self.resolveProEntitlement(licenseState)
        self.tariffFeatures = Self.resolveTariffFeatures(
            licenseState: licenseState,
            isProEntitlementActive: isProEntitlementActive
        )
    }

    public static func load(store: LocalStoring = try! SecureLocalStore()) throws -> OffsendRuntimeContext {
        OffsendRuntimeContext(
            settings: try store.loadSettings(),
            customDictionaries: try store.loadCustomDictionaries(),
            licenseState: try store.loadLicenseState()
        )
    }

    private static func resolveProEntitlement(_ licenseState: LicenseState) -> Bool {
        guard licenseState.plan == .pro else { return false }
        return LicenseOfflineEntitlement.isProUnlocked(
            expiresAt: licenseState.subscriptionExpiresAt,
            graceUntil: licenseState.graceUntil
        )
    }

    private static func resolveTariffFeatures(
        licenseState: LicenseState,
        isProEntitlementActive: Bool
    ) -> LicenseTariffFeatures {
        guard licenseState.plan == .pro, isProEntitlementActive else {
            return .freeTier
        }
        return .proWithoutFeatureMap
    }
}
