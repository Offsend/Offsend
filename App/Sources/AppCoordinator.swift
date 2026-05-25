import AnalyticsCore
import AppUIKit
import AppKit
import ClipboardService
import DetectionCore
import Foundation
import HotkeyService
import LicenseCore
import MaskingCore
import PasteService
import PermissionsService
import RiskScoringCore
import ServiceManagement
import StorageCore

#if DEBUG
enum DebugLicenseAPIEnvironment: String, CaseIterable, Identifiable {
    case production
    case develop

    var id: String { rawValue }

    static let userDefaultsKey = "io.offsend.debug.licenseAPIEnvironment"

    static func loadFromUserDefaults() -> Self {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? Self.production.rawValue
        return Self(rawValue: raw) ?? .production
    }

    var licenseConfiguration: LicenseConfiguration {
        switch self {
        case .production: .production
        case .develop: .develop
        }
    }
}

enum DebugTariffFeatureOverrides {
    static let userDefaultsKey = "io.offsend.debug.tariffFeatureOverrides"

    static func load() -> [LicenseTariffFeatureKey: Bool] {
        guard let raw = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Bool] else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard let featureKey = LicenseTariffFeatureKey(rawValue: key) else { return nil }
            return (featureKey, value)
        })
    }

    static func save(_ overrides: [LicenseTariffFeatureKey: Bool]) {
        let raw = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(raw, forKey: userDefaultsKey)
    }
}
#endif

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var settings: AppSettings
    @Published var customDictionaries: [CustomDictionaryItem]
    @Published var licenseState: LicenseState
    @Published var lastStatusMessage = OffsendStrings.statusReady {
        didSet {
            refreshMenuBarStatusItem()
        }
    }
    @Published var mappingSummaries: [StoredMappingSummary] = []
    @Published var clipboardAssessmentStatus: ClipboardAssessmentStatus = .idle {
        didSet {
            refreshMenuBarStatusItem()
        }
    }

    let clipboardService = ClipboardService()
    let pasteService = PasteService()
    let permissionsService = PermissionsService()
    let hotkeyService = HotkeyService()
    let detectionEngine = DetectionEngine()
    let riskEngine = RiskScoringEngine()
    let maskingEngine = MaskingEngine()
    let dockIconVisibilityService = DockIconVisibilityService()
    let menuBarStatusItemController = MenuBarStatusItemController()
    let store: LocalStoring
    let analytics: AppAnalytics
    var licenseService: LicenseService

    @Published var licenseActivationDeviceLimit: [LicenseActivatedDevice] = []
    /// `nil` = normal license UI. Non-`nil` (including `""`) = post-checkout deeplink flow with optional email prefill.
    @Published var licensePostCheckoutFlowEmail: String?
    @Published var licensePricing = LicensePricingPresentation.fallback(
        LicensePricingFallbackStrings(
            headline: OffsendStrings.settingsLicensePricingFallbackHeadline,
            subheadline: OffsendStrings.settingsLicensePricingFallbackSubheadline,
            buyButtonTitle: OffsendStrings.settingsLicensePricingFallbackBuy
        ),
        defaultPlanId: "pro_annual"
    )

    /// Feature flags from the active catalog plan (`/pricing` → `features`), for Pro; free tier is always denied.
    var tariffFeatures: LicenseTariffFeatures {
        let resolved = LicenseTariffFeaturesResolver.resolve(
            isPro: licenseState.plan == .pro,
            pricing: licensePricing
        )
        #if DEBUG
        return Self.applyingDebugTariffOverrides(resolved, overrides: debugTariffFeatureOverrides)
        #else
        return resolved
        #endif
    }

    #if DEBUG
    @Published var debugTariffFeatureOverrides: [LicenseTariffFeatureKey: Bool] = DebugTariffFeatureOverrides.load()
    #endif

    private static let marketingAppVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private let sparkleUpdater = OffsendSparkleUpdater()

    private var openSettingsWindowAction: (() -> Void)?

    private var safePastePanel: SafePastePanelController?
    private var clipboardStatusPanel: ClipboardStatusPanelController?
    private var clipboardAssessmentSnapshot: ClipboardAssessmentSnapshot?
    private var lastAppliedLaunchAtLoginPreference: Bool?

    init() {
        var store: LocalStoring
        var initialSettings: AppSettings
        do {
            store = try SecureLocalStore()
            initialSettings = try store.loadSettings()
            self.settings = initialSettings
            self.customDictionaries = try store.loadCustomDictionaries()
            self.licenseState = try store.loadLicenseState()
            try store.cleanupExpiredMappings()
            self.mappingSummaries = try store.mappingSummaries()
        } catch {
            store = InMemoryLocalStore()
            initialSettings = .default
            self.settings = initialSettings
            self.customDictionaries = []
            self.licenseState = LicenseState()
            self.lastStatusMessage = OffsendStrings.statusStorageUnavailable(error.localizedDescription)
        }

        #if DEBUG
        licenseService = LicenseService(configuration: DebugLicenseAPIEnvironment.loadFromUserDefaults().licenseConfiguration)
        #else
        licenseService = LicenseService()
        #endif

        self.store = store
        self.analytics = AppAnalytics(
            local: LocalAnalytics(store: store),
            product: TelemetryDeckAnalytics(isEnabled: initialSettings.analyticsOptIn)
        )
        self.lastAppliedLaunchAtLoginPreference = settings.launchAtLogin

        menuBarStatusItemController.configureActions(
            safePaste: { [weak self] in self?.performSafePaste() },
            showClipboardStatus: { [weak self] in self?.showClipboardStatus() },
            restore: { [weak self] in self?.restorePlaceholders() },
            refreshBeforeOpen: { [weak self] in self?.refreshMenuBarStatusItem() },
            toggleProtection: { [weak self] in
                guard let self else { return }
                settings.protectionEnabled.toggle()
                saveSettings()
            },
            toggleClipboardMonitoring: { [weak self] in
                guard let self else { return }
                settings.clipboardMonitoringEnabled.toggle()
                saveSettings()
            },
            checkForUpdates: { [weak self] sender in
                self?.sparkleUpdater.checkForUpdates(sender: sender)
            }
        )

        if !settings.hasCompletedOnboarding {
            settings.clipboardMonitoringEnabled = true
        }

        hotkeyService.register(
            safePaste: { [weak self] in self?.performSafePaste() },
            restore: { [weak self] in self?.restorePlaceholders() }
        )
        applyClipboardMonitoringPreference()
        refreshMenuBarStatusItem()

        Task { await performStartupLicenseTasks() }
    }

    func checkForSparkleUpdates(sender: Any?) {
        sparkleUpdater.checkForUpdates(sender: sender)
    }

    func performSafePaste() {
        guard settings.protectionEnabled else {
            pasteOriginalFromClipboard()
            return
        }

        guard let text = clipboardService.readString(), !text.isEmpty else {
            lastStatusMessage = OffsendStrings.statusClipboardHasNoText
            return
        }

        if let snapshot = clipboardAssessmentSnapshot(for: text) {
            analytics.track(.safePasteUsed(
                riskLevel: snapshot.assessment.level,
                entityCount: snapshot.detection.entities.count,
                usedCachedScan: true
            ))
            handleSafePaste(snapshot: snapshot)
            return
        }

        let (detection, assessment) = assessClipboardText(text)
        rememberClipboardAssessment(text: text, detection: detection, assessment: assessment)
        analytics.track(.safePasteUsed(
            riskLevel: assessment.level,
            entityCount: detection.entities.count,
            usedCachedScan: false
        ))

        handleSafePaste(snapshot: ClipboardAssessmentSnapshot(text: text, detection: detection, assessment: assessment), showsPopupForNewRisk: true)
    }

    func restorePlaceholders() {
        guard let text = clipboardService.readString(), !text.isEmpty else {
            lastStatusMessage = OffsendStrings.statusClipboardHasNoTextToRestore
            return
        }

        do {
            guard let restored = try store.restore(text: text) else {
                lastStatusMessage = OffsendStrings.statusNoMatchingMapping
                return
            }
            analytics.track(.restoreUsed)
            let pastedIntoActiveApp = settings.restoreBehavior == .pasteIntoActiveApp && pasteService.canPasteIntoActiveApp
            if pastedIntoActiveApp {
                pasteText(restored)
            } else {
                clipboardService.writeString(restored)
            }
            lastStatusMessage = OffsendStrings.statusPlaceholdersRestored

            if pastedIntoActiveApp, settings.preserveOriginalClipboard {
                syncClipboardAssessmentStatus(for: restored)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                    self?.syncClipboardAssessmentFromCurrentPasteboard()
                }
            } else {
                syncClipboardAssessmentStatus(for: restored)
            }
        } catch {
            lastStatusMessage = OffsendStrings.statusRestoreFailed(error.localizedDescription)
        }
    }

    func showClipboardStatus() {
        guard let text = clipboardService.readString(), !text.isEmpty else {
            lastStatusMessage = OffsendStrings.statusClipboardHasNoText
            refreshMenuBarStatusItem()
            return
        }

        let (detection, assessment) = assessClipboardText(text)
        rememberClipboardAssessment(text: text, detection: detection, assessment: assessment)
        guard !detection.entities.isEmpty, assessment.recommendedAction != .allow else {
            clipboardAssessmentStatus = .safe
            lastStatusMessage = detection.wasTruncated ? OffsendStrings.statusClipboardLooksSafeScanned : OffsendStrings.statusClipboardLooksSafe
            showClipboardStatusPopup(assessment: assessment, wasTruncated: detection.wasTruncated)
            return
        }

        clipboardAssessmentStatus = resolvedClipboardAssessmentStatus(for: detection, assessment: assessment)
        lastStatusMessage = OffsendStrings.statusClipboardRiskDetected(AppLocalization.riskLevelName(assessment.level))
        showSafePastePopup(originalText: detection.scannedText, entities: detection.entities, assessment: assessment, wasTruncated: detection.wasTruncated)
    }

    func maskAndPaste(originalText: String, entities: [SensitiveEntity]) {
        let result = maskingEngine.mask(text: originalText, entities: entities, ttl: settings.mappingTTL)
        do {
            try store.saveMapping(result)
            try refreshMappingSummaries()
            analytics.track(.maskApplied)
        } catch {
            lastStatusMessage = OffsendStrings.statusCouldNotSaveMapping(error.localizedDescription)
        }

        if pasteService.canPasteIntoActiveApp {
            pasteText(result.maskedText)
            lastStatusMessage = OffsendStrings.statusMaskedTextPasted
            if settings.preserveOriginalClipboard {
                syncClipboardAssessmentStatus(for: result.maskedText)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                    self?.syncClipboardAssessmentFromCurrentPasteboard()
                }
            } else {
                syncClipboardAssessmentStatus(for: result.maskedText)
            }
        } else {
            clipboardService.writeString(result.maskedText)
            lastStatusMessage = OffsendStrings.statusAccessibilityMissingSafeVersionCopied
            syncClipboardAssessmentStatus(for: result.maskedText)
        }
        recordFreeTierMaskedPasteForUsageQuota()
    }

    func pasteOriginal(originalText: String, assessment: RiskAssessment) {
        guard !assessment.hasCriticalSecret || settings.allowPasteOriginalForCriticalSecrets else {
            lastStatusMessage = OffsendStrings.statusCriticalSecretBlocked
            return
        }
        analytics.track(.pasteOriginalChosen(riskLevel: assessment.level))
        pasteText(originalText)
        lastStatusMessage = OffsendStrings.statusOriginalTextPasted
    }

    func copySafeVersion(originalText: String, entities: [SensitiveEntity]) {
        let result = maskingEngine.mask(text: originalText, entities: entities, ttl: settings.mappingTTL)
        try? store.saveMapping(result)
        try? refreshMappingSummaries()
        clipboardService.writeString(result.maskedText)
        analytics.track(.maskApplied)
        lastStatusMessage = OffsendStrings.statusSafeVersionCopied

        syncClipboardAssessmentStatus(for: result.maskedText)
        recordFreeTierMaskedPasteForUsageQuota()
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        saveSettings()
        analytics.track(.onboardingCompleted)
    }

    func copyOnboardingSampleToClipboard(_ text: String) {
        clipboardService.writeString(text)

        guard settings.protectionEnabled, settings.clipboardMonitoringEnabled else {
            lastStatusMessage = OffsendStrings.statusSampleCopied
            return
        }

        handleMonitoredClipboardText(text)
    }

    func saveSettings() {
        analytics.setProductAnalyticsEnabled(settings.analyticsOptIn)
        do {
            try store.saveSettings(settings)
            if settings.launchAtLogin != lastAppliedLaunchAtLoginPreference {
                try applyLaunchAtLoginPreference()
                lastAppliedLaunchAtLoginPreference = settings.launchAtLogin
            }
            applyClipboardMonitoringPreference()
            lastStatusMessage = OffsendStrings.statusSettingsSaved
            refreshMenuBarStatusItem()
        } catch {
            lastStatusMessage = OffsendStrings.statusSettingsSaveFailed(error.localizedDescription)
        }
    }

    func saveCustomDictionaries() {
        do {
            try store.saveCustomDictionaries(customDictionaries)
            lastStatusMessage = OffsendStrings.statusCustomDictionariesSaved
        } catch {
            lastStatusMessage = OffsendStrings.statusDictionarySaveFailed(error.localizedDescription)
        }
    }

    func clearAllMappings() {
        do {
            try store.clearMappings()
            try refreshMappingSummaries()
            lastStatusMessage = OffsendStrings.statusLocalMappingsCleared
        } catch {
            lastStatusMessage = OffsendStrings.statusCouldNotClearMappings(error.localizedDescription)
        }
    }

    func clearLocalHistory() {
        do {
            try store.clearEvents()
            lastStatusMessage = OffsendStrings.statusLocalCountersCleared
        } catch {
            lastStatusMessage = OffsendStrings.statusCouldNotClearLocalCounters
        }
    }

    func exportPrivacyReport() -> String {
        let events = (try? store.loadEvents()) ?? []
        return OffsendStrings.privacyReportBody(
            settings.clipboardMonitoringEnabled ? OffsendStrings.commonOnLowercase : OffsendStrings.commonOffLowercase,
            mappingSummaries.count,
            customDictionaries.count,
            events.count
        )
    }

    func hasOffsendLicenseToken() -> Bool {
        guard let token = try? licenseService.storedLicenseToken() else { return false }
        return !token.isEmpty
    }

    func canOpenLicenseBillingPortal() -> Bool {
        (try? licenseService.canOpenBillingPortal()) ?? false
    }

    func licenseSettingsScreenDidAppear() async {
        persistFreeTierMaskedUsageMonthReconciliationIfNeeded()
        await refreshLicensePricingCatalog()
        await refreshLicenseFromServerIfStale(trigger: .settingsLicenseScreen)
    }

    @discardableResult
    func requestLicenseActivationCode(email: String) async -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.split(separator: "@").count == 2, trimmed.count > 4 else {
            lastStatusMessage = OffsendStrings.statusLicenseInvalidEmail
            return false
        }
        licenseActivationDeviceLimit = []
        do {
            try await licenseService.requestActivationCode(email: trimmed)
            lastStatusMessage = OffsendStrings.statusActivationRequestAcknowledged
            return true
        } catch {
            lastStatusMessage = OffsendStrings.statusLicenseValidateFailed(error.localizedDescription)
            return false
        }
    }

    func verifyLicenseActivation(email: String, code: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = code.filter(\.isNumber)
        guard trimmedEmail.contains("@"), digits.count == 6 else {
            lastStatusMessage = OffsendStrings.statusLicenseInvalidEmail
            return
        }
        licenseActivationDeviceLimit = []
        do {
            _ = try licenseService.deviceId()
            let result = try await licenseService.verifyActivationCode(
                email: trimmedEmail,
                code: String(digits.prefix(6)),
                deviceName: hostDeviceName(),
                appVersion: Self.marketingAppVersion,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString
            )
            try licenseService.persistVerifiedLicense(token: result.licenseToken)
            applySuccessfulVerification(result)
            licensePostCheckoutFlowEmail = nil
            lastStatusMessage = OffsendStrings.statusLicenseActivated
        } catch let error as LicenseServiceError {
            switch error {
            case .deviceLimitReached(let devices):
                licenseActivationDeviceLimit = devices
                lastStatusMessage = OffsendStrings.statusLicenseDeviceLimit
            default:
                lastStatusMessage = OffsendStrings.statusLicenseVerifyFailed(error.localizedDescription)
            }
        } catch {
            lastStatusMessage = OffsendStrings.statusLicenseVerifyFailed(error.localizedDescription)
        }
    }

    func openProCheckout(prefillEmail: String?) async {
        let trimmed = prefillEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email: String? = {
            guard let trimmed, trimmed.contains("@") else { return nil }
            return trimmed
        }()
        do {
            let url = try await licenseService.createCheckout(email: email, planId: licensePricing.defaultCheckoutPlanId)
            NSWorkspace.shared.open(url)
            lastStatusMessage = OffsendStrings.statusLicenseCheckoutOpened
        } catch {
            lastStatusMessage = OffsendStrings.statusLicenseCheckoutFailed(error.localizedDescription)
        }
    }

    func openBillingPortalFromLicense() async {
        do {
            guard try licenseService.canOpenBillingPortal() else {
                lastStatusMessage = OffsendStrings.statusLicensePortalUnavailable
                return
            }
            let url = try await licenseService.billingPortalURL()
            NSWorkspace.shared.open(url)
            lastStatusMessage = OffsendStrings.statusLicensePortalOpened
        } catch {
            lastStatusMessage = OffsendStrings.statusLicensePortalFailed(error.localizedDescription)
        }
    }

    func refreshLicenseFromServer() async {
        await refreshLicenseFromServerIfStale(trigger: .userPull)
    }

    func switchToFreePlan() {
        try? licenseService.clearProLicense()
        var state = licenseState
        state.plan = .free
        state.subscriptionExpiresAt = nil
        state.graceUntil = nil
        state.licenseBillingState = nil
        state.licenseStatus = nil
        state.activatedAt = nil
        state.lastLicenseValidationAt = nil
        licenseState = state
        licenseActivationDeviceLimit = []
        try? store.saveLicenseState(state)
        lastStatusMessage = OffsendStrings.statusLicenseUseFree
    }

    func refreshMappingSummaries() throws {
        mappingSummaries = try store.mappingSummaries()
    }

    func menuBarIcon() -> NSImage {
        MenuBarStatusItemController.compositeStatusBarIcon(
            base: OffsendAsset.Images.StatusBar.normal.image,
            mask: OffsendAsset.Images.StatusBar.mask.image,
            dotColor: menuBarStatusDotColor()
        )
    }

    private func menuBarStatusDotColor() -> NSColor {
        switch clipboardAssessmentStatus {
        case .idle:
            return .labelColor
        case .safe:
            return .labelColor
        case .warning:
            return .systemOrange
        case .risk:
            return .systemRed
        }
    }

//    func menuBarIconColor() -> Color {
//        switch clipboardAssessmentStatus {
////        case .safe:
////            return .green
//        case .warning:
//            return Color(NSColor.systemOrange)
//        case .risk:
//            return Color(NSColor.systemRed)
//        case .idle, .safe:
//            return Color(nsColor: .labelColor)
//        }
//    }

    func configureMenuBarStatusItem(
        openOnboarding: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openDirectoryCheck: @escaping () -> Void
    ) {
        OffsendApplicationDelegate.coordinator = self
        openSettingsWindowAction = openSettings
        menuBarStatusItemController.configureWindowActions(
            openOnboarding: openOnboarding,
            openSettings: openSettings,
            openDirectoryCheck: openDirectoryCheck
        )
        refreshMenuBarStatusItem()
    }

    func clearLicensePostCheckoutFlow() {
        licensePostCheckoutFlowEmail = nil
    }

    func handleOffsendURL(_ url: URL) {
        guard let link = OffsendDeepLinkParser.parse(url) else { return }
        switch link {
        case .checkoutSuccess(let prefill):
            guard licenseState.plan != .pro else { return }
            let trimmed = prefill?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            licensePostCheckoutFlowEmail = trimmed.isEmpty ? nil : trimmed
            openSettingsWindowAction?()
        }
    }

    private enum LicenseRemoteRefreshTrigger {
        case appLaunch
        case settingsLicenseScreen
        case userPull
    }

    private func hostDeviceName() -> String? {
        guard let name = Host.current().localizedName, !name.isEmpty else { return nil }
        return name
    }

    private func persistFreeTierMaskedUsageMonthReconciliationIfNeeded() {
        guard licenseState.plan == .free else { return }
        var state = licenseState
        let before = state
        state.reconcileFreeTierMaskedUsageCountForCurrentMonth()
        guard state != before else { return }
        licenseState = state
        try? store.saveLicenseState(state)
    }

    private func recordFreeTierMaskedPasteForUsageQuota() {
        guard licenseState.plan == .free else { return }
        var state = licenseState
        state.reconcileFreeTierMaskedUsageCountForCurrentMonth()
        state.maskedThisMonth += 1
        licenseState = state
        try? store.saveLicenseState(state)
    }

    private func performStartupLicenseTasks() async {
        persistFreeTierMaskedUsageMonthReconciliationIfNeeded()
        reconcileLicensePlanWithOfflineEntitlement()
        async let pricing: Void = refreshLicensePricingCatalog()
        async let validate: Void = refreshLicenseFromServerIfStale(trigger: .appLaunch)
        _ = await (pricing, validate)
    }

    private func refreshLicensePricingCatalog() async {
        let locale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        licensePricing = await licenseService.loadPricingPresentation(
            appVersion: Self.marketingAppVersion,
            localeIdentifier: locale,
            currencyCode: nil,
            fallback: LicensePricingFallbackStrings(
                headline: OffsendStrings.settingsLicensePricingFallbackHeadline,
                subheadline: OffsendStrings.settingsLicensePricingFallbackSubheadline,
                buyButtonTitle: OffsendStrings.settingsLicensePricingFallbackBuy
            )
        )
    }

    private func reconcileLicensePlanWithOfflineEntitlement() {
        let token = (try? licenseService.storedLicenseToken()) ?? ""
        var state = licenseState
        guard !token.isEmpty else {
            if state.plan != .free {
                state.plan = .free
                licenseState = state
                try? store.saveLicenseState(state)
            }
            return
        }
        let unlocked = LicenseOfflineEntitlement.isProUnlocked(
            expiresAt: state.subscriptionExpiresAt,
            graceUntil: state.graceUntil
        )
        let newPlan: LicenseState.Plan = unlocked ? .pro : .free
        if newPlan != state.plan {
            state.plan = newPlan
            licenseState = state
            try? store.saveLicenseState(state)
        }
    }

    private func applyLicenseValidationResult(_ result: LicenseValidateResult) {
        var state = licenseState
        if let exp = result.expiresAt { state.subscriptionExpiresAt = exp }
        if let grace = result.graceUntil { state.graceUntil = grace }
        state.licenseBillingState = result.billingState
        state.licenseStatus = result.licenseStatus
        state.lastLicenseValidationAt = Date()
        let token = (try? licenseService.storedLicenseToken()) ?? ""
        let unlocked = !token.isEmpty && LicenseOfflineEntitlement.isProUnlocked(
            expiresAt: state.subscriptionExpiresAt,
            graceUntil: state.graceUntil
        )
        state.plan = unlocked ? .pro : .free
        licenseState = state
        try? store.saveLicenseState(state)
    }

    private func applySuccessfulVerification(_ success: LicenseVerifySuccess) {
        var state = licenseState
        state.plan = .pro
        state.subscriptionExpiresAt = success.expiresAt
        state.graceUntil = success.graceUntil
        state.licenseBillingState = "active"
        state.licenseStatus = "active"
        state.activatedAt = Date()
        state.lastLicenseValidationAt = Date()
        licenseState = state
        try? store.saveLicenseState(state)
    }

    private func refreshLicenseFromServerIfStale(trigger: LicenseRemoteRefreshTrigger) async {
        guard let token = try? licenseService.storedLicenseToken(), !token.isEmpty else { return }
        let forceImmediate: Bool
        switch trigger {
        case .userPull, .settingsLicenseScreen:
            forceImmediate = true
        case .appLaunch:
            forceImmediate = false
        }
        if !forceImmediate {
            let day: TimeInterval = 24 * 3600
            if let last = licenseState.lastLicenseValidationAt, Date().timeIntervalSince(last) < day {
                return
            }
        }
        do {
            let result = try await licenseService.validateLicense(appVersion: Self.marketingAppVersion)
            applyLicenseValidationResult(result)
            if trigger == .userPull {
                lastStatusMessage = OffsendStrings.statusLicenseValidated
            }
        } catch {
            if trigger == .userPull {
                lastStatusMessage = OffsendStrings.statusLicenseValidateFailed(error.localizedDescription)
            }
        }
    }

    private func pasteOriginalFromClipboard() {
        guard pasteService.canPasteIntoActiveApp else {
            lastStatusMessage = OffsendStrings.statusAccessibilityMissingClipboardUnchanged
            return
        }
        pasteService.pasteIntoActiveApp()
    }

    @discardableResult
    private func handleNoRiskClipboardText(_ text: String) -> String? {
        switch settings.defaultNoRiskAction {
        case .pasteOriginal:
            guard pasteService.canPasteIntoActiveApp else {
                return OffsendStrings.statusAccessibilityMissingClipboardUnchanged
            }
            pasteService.pasteIntoActiveApp()
            return nil
        case .copyOriginal:
            clipboardService.writeString(text)
            return nil
        case .showToast:
            return nil
        }
    }

    private func pasteText(_ text: String) {
        if settings.preserveOriginalClipboard {
            clipboardService.temporarilyWrite(text, restoreAfter: 0.8) {
                self.pasteService.pasteIntoActiveApp()
            }
        } else {
            clipboardService.writeString(text)
            pasteService.pasteIntoActiveApp()
        }
    }

    private func handleMonitoredClipboardText(_ text: String) {
        guard settings.protectionEnabled, settings.clipboardMonitoringEnabled else {
            clipboardAssessmentStatus = .idle
            return
        }

        let (detection, assessment) = assessClipboardText(text)
        rememberClipboardAssessment(text: text, detection: detection, assessment: assessment)

        if let excludedApplicationName = frontmostExcludedClipboardApplicationName() {
            clipboardAssessmentStatus = .idle
            lastStatusMessage = OffsendStrings.statusClipboardMonitoringPausedForApp(excludedApplicationName)
            refreshMenuBarStatusItem()
            return
        }

        guard !detection.entities.isEmpty, assessment.recommendedAction != .allow else {
            clipboardAssessmentStatus = .safe
            lastStatusMessage = detection.wasTruncated ? OffsendStrings.statusClipboardLooksSafeScanned : OffsendStrings.statusClipboardLooksSafe
            return
        }

        clipboardAssessmentStatus = resolvedClipboardAssessmentStatus(for: detection, assessment: assessment)
        lastStatusMessage = OffsendStrings.statusClipboardRiskDetected(AppLocalization.riskLevelName(assessment.level))
        showSafePastePopup(originalText: detection.scannedText, entities: detection.entities, assessment: assessment, wasTruncated: detection.wasTruncated)
    }

    private func resolvedClipboardAssessmentStatus(for detection: DetectionResult, assessment: RiskAssessment) -> ClipboardAssessmentStatus {
        guard !detection.entities.isEmpty else { return .safe }
        switch assessment.recommendedAction {
        case .allow:
            return .idle
        case .mask:
            return .safe
        case .warn:
            return .warning
        case .block:
            return .risk
        }
    }

    private func assessClipboardText(_ text: String) -> (DetectionResult, RiskAssessment) {
        let detectionOptions = DetectionOptions(
            enabledTypes: settings.enabledDetectors,
            customDictionaries: customDictionaries
        )
        let detection = detectionEngine.scan(DetectionRequest(text: text, options: detectionOptions))
        return (detection, riskEngine.assess(detection.entities))
    }

    private func rememberClipboardAssessment(text: String, detection: DetectionResult, assessment: RiskAssessment) {
        clipboardAssessmentSnapshot = ClipboardAssessmentSnapshot(text: text, detection: detection, assessment: assessment)
    }

    private func syncClipboardAssessmentStatus(for text: String) {
        let (detection, assessment) = assessClipboardText(text)
        rememberClipboardAssessment(text: text, detection: detection, assessment: assessment)

        guard settings.protectionEnabled, settings.clipboardMonitoringEnabled else {
            clipboardAssessmentStatus = .idle
            return
        }

        if frontmostExcludedClipboardApplicationName() != nil {
            clipboardAssessmentStatus = .idle
            return
        }

        guard !detection.entities.isEmpty, assessment.recommendedAction != .allow else {
            clipboardAssessmentStatus = .safe
            return
        }

        clipboardAssessmentStatus = resolvedClipboardAssessmentStatus(for: detection, assessment: assessment)
    }

    private func syncClipboardAssessmentFromCurrentPasteboard() {
        guard let text = clipboardService.readString(), !text.isEmpty else {
            clipboardAssessmentStatus = .idle
            return
        }
        syncClipboardAssessmentStatus(for: text)
    }

    private func clipboardAssessmentSnapshot(for text: String) -> ClipboardAssessmentSnapshot? {
        guard let snapshot = clipboardAssessmentSnapshot, snapshot.text == text else {
            return nil
        }

        return snapshot
    }

    private func handleSafePaste(snapshot: ClipboardAssessmentSnapshot, showsPopupForNewRisk: Bool = false) {
        guard snapshot.hasRisk else {
            clipboardAssessmentStatus = .safe
            if let statusOverride = handleNoRiskClipboardText(snapshot.text) {
                lastStatusMessage = statusOverride
            } else {
                lastStatusMessage = snapshot.detection.wasTruncated ? OffsendStrings.statusNoSensitiveDataScanned : OffsendStrings.statusNoSensitiveData
            }
            return
        }

        clipboardAssessmentStatus = resolvedClipboardAssessmentStatus(for: snapshot.detection, assessment: snapshot.assessment)

        guard !showsPopupForNewRisk else {
            showSafePastePopup(
                originalText: snapshot.detection.scannedText,
                entities: snapshot.detection.entities,
                assessment: snapshot.assessment,
                wasTruncated: snapshot.detection.wasTruncated
            )
            return
        }

        safePastePanel?.close()
        maskAndPaste(originalText: snapshot.detection.scannedText, entities: snapshot.detection.entities)
    }

    private func frontmostExcludedClipboardApplicationName() -> String? {
        guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return nil
        }

        return ExcludedClipboardApplication.matches(
            bundleIdentifier: bundleIdentifier,
            in: settings.excludedClipboardApplications
        )?.displayName
    }

    private func showSafePastePopup(
        originalText: String,
        entities: [SensitiveEntity],
        assessment: RiskAssessment,
        wasTruncated: Bool
    ) {
        safePastePanel = SafePastePanelController(
            originalText: originalText,
            entities: entities,
            assessment: assessment,
            wasTruncated: wasTruncated,
            onMaskAndPaste: { [weak self] in self?.maskAndPaste(originalText: originalText, entities: entities) },
            onCopySafeVersion: { [weak self] in self?.copySafeVersion(originalText: originalText, entities: entities) },
            onPasteOriginal: { [weak self] in self?.pasteOriginal(originalText: originalText, assessment: assessment) },
            onCancel: { [weak self] in self?.lastStatusMessage = OffsendStrings.statusSafePasteCancelled }
        )
        safePastePanel?.show(from: menuBarStatusItemController.statusItem)
        refreshMenuBarStatusItem()
    }

    private func showClipboardStatusPopup(assessment: RiskAssessment, wasTruncated: Bool) {
        clipboardStatusPanel = ClipboardStatusPanelController(
            title: OffsendStrings.clipboardStatusSafeTitle,
            message: wasTruncated ? OffsendStrings.clipboardStatusSafeMessageScanned : OffsendStrings.clipboardStatusSafeMessage,
            score: min(assessment.score, 100),
            onClose: { [weak self] in self?.clipboardStatusPanel = nil }
        )
        clipboardStatusPanel?.show(from: menuBarStatusItemController.statusItem)
        refreshMenuBarStatusItem()
    }

    private func clipboardStatusMenuTitle(clipboardText: String?) -> String {
        guard let text = clipboardText, !text.isEmpty else {
            return OffsendStrings.menuClipboardStatusEmpty
        }

        switch clipboardAssessmentStatus {
        case .idle:
            return OffsendStrings.menuClipboardStatusReady
        case .safe:
            return OffsendStrings.menuClipboardStatusSafe
        case .warning:
            return OffsendStrings.menuClipboardStatusWarning
        case .risk:
            return OffsendStrings.menuClipboardStatusRisk
        }
    }

    private func refreshMenuBarStatusItem() {
        let clipboardText = clipboardService.readString()
        menuBarStatusItemController.update(
            icon: menuBarIcon(),
            iconTint: menuBarStatusItemIconTint(),
            settings: settings,
            clipboardStatusTitle: clipboardStatusMenuTitle(clipboardText: clipboardText),
            isClipboardStatusActionEnabled: !(clipboardText?.isEmpty ?? true),
            lastStatusMessage: lastStatusMessage
        )
    }

    /// Dot color is baked in `menuBarIcon()` via the mask asset; keep `nil` so the composite bitmap is not re-tinted as a single template.
    private func menuBarStatusItemIconTint() -> NSColor? {
        nil
    }

    private func applyClipboardMonitoringPreference() {
        guard settings.protectionEnabled, settings.clipboardMonitoringEnabled else {
            clipboardService.stopMonitoring()
            clipboardAssessmentStatus = .idle
            refreshMenuBarStatusItem()
            return
        }

        clipboardService.startMonitoring { [weak self] text in
            Task { @MainActor [weak self] in
                self?.handleMonitoredClipboardText(text)
            }
        }
    }

    private func applyLaunchAtLoginPreference() throws {
        if settings.launchAtLogin {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

#if DEBUG
extension AppCoordinator {
    private static func applyingDebugTariffOverrides(
        _ features: LicenseTariffFeatures,
        overrides: [LicenseTariffFeatureKey: Bool]
    ) -> LicenseTariffFeatures {
        guard !overrides.isEmpty else { return features }
        var result = features
        for (key, value) in overrides {
            switch key {
            case .safePasteUnlimited:
                result.safePasteUnlimited = value
            case .advancedDetectors:
                result.advancedDetectors = value
            case .customDictionaries:
                result.customDictionaries = value
            case .workspaceAuditFull:
                result.workspaceAuditFull = value
            case .workspaceAuditAutofix:
                result.workspaceAuditAutofix = value
            }
        }
        return result
    }

    func debugSetTariffFeatureOverride(_ key: LicenseTariffFeatureKey, enabled: Bool) {
        debugTariffFeatureOverrides[key] = enabled
        DebugTariffFeatureOverrides.save(debugTariffFeatureOverrides)
    }

    var debugLicenseAPIEnvironment: DebugLicenseAPIEnvironment {
        DebugLicenseAPIEnvironment.loadFromUserDefaults()
    }

    func debugSetLicenseAPIEnvironment(_ environment: DebugLicenseAPIEnvironment) {
        UserDefaults.standard.set(environment.rawValue, forKey: DebugLicenseAPIEnvironment.userDefaultsKey)
        licenseService = LicenseService(configuration: environment.licenseConfiguration)
        objectWillChange.send()
        Task {
            await refreshLicensePricingCatalog()
            await refreshLicenseFromServerIfStale(trigger: .settingsLicenseScreen)
        }
    }

    /// JWT-shaped string with `{}` payload; not valid for `/license/validate`, but satisfies local token presence for Pro gating.
    private static let debugSyntheticLicenseJWT: String = {
        let emptyJSON = Data("{}".utf8)
        let segment = emptyJSON.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(segment).\(segment).debug"
    }()

    /// Sets Free (clears token) or simulated Pro (synthetic token + active subscription dates) for local UI and entitlement checks.
    /// Also clears any sticky per-feature overrides so the picker reflects the chosen plan's baseline.
    func debugApplySimulatedLicensePlan(_ plan: LicenseState.Plan) {
        debugTariffFeatureOverrides = [:]
        DebugTariffFeatureOverrides.save([:])

        switch plan {
        case .free:
            switchToFreePlan()
        case .pro:
            do {
                _ = try licenseService.deviceId()
                try licenseService.persistVerifiedLicense(token: Self.debugSyntheticLicenseJWT)
                var state = licenseState
                let farFuture = Date().addingTimeInterval(365 * 24 * 60 * 60)
                state.plan = .pro
                state.subscriptionExpiresAt = farFuture
                state.graceUntil = nil
                state.licenseBillingState = "active"
                state.licenseStatus = "active"
                state.activatedAt = Date()
                state.lastLicenseValidationAt = Date()
                licenseState = state
                licenseActivationDeviceLimit = []
                try? store.saveLicenseState(state)
            } catch {
                lastStatusMessage = error.localizedDescription
            }
        }
    }
}
#endif
