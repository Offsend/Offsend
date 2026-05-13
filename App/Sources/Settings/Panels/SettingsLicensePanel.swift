import AppKit
import AppUIKit
import LicenseCore
import StorageCore
import SwiftUI

enum SettingsLicenseLayout {
    static let freeMonthlyLimit = 50
    /// Shown when pricing has no `deviceLimit` (marketing copy only).
    static let proMarketingMacLimitFallback = 3
    static let planCardsMinHeight: CGFloat = 248
}

private enum ActivationStep {
    case collectEmail
    case checkEmail
}

struct SettingsLicensePanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    @State private var activationEmail = ""
    @State private var activationCode = ""
    @State private var activationStep: ActivationStep = .collectEmail

    private var plan: LicenseState.Plan {
        coordinator.licenseState.plan
    }

    private var graceDate: Date? {
        coordinator.licenseState.graceUntil ?? coordinator.licenseState.offlineGraceExpiresAt
    }

    private var entitlement: LicenseOfflineEntitlement {
        LicenseOfflineEntitlement.resolve(
            expiresAt: coordinator.licenseState.subscriptionExpiresAt,
            graceUntil: graceDate
        )
    }

    private var showExpiredTokenRecovery: Bool {
        plan == .free && coordinator.hasOffsendLicenseToken()
    }

    private var billingPastDue: Bool {
        coordinator.licenseState.licenseBillingState == "past_due"
    }

    private var showPostCheckoutActivation: Bool {
        coordinator.licensePostCheckoutFlowEmail != nil && plan == .free && !showExpiredTokenRecovery
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if plan == .pro {
                proStatusHeader
                    .padding(.bottom, 18)
            } else if showExpiredTokenRecovery {
                expiredTokenHeader
                    .padding(.bottom, 18)
            } else {
                freePlanBanner
                    .padding(.bottom, 16)
            }

            if showPostCheckoutActivation {
                PostCheckoutLicenseActivationCard()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 22)
            } else {
                planCardsRow
                    .padding(.bottom, 22)

                if plan == .free, !showExpiredTokenRecovery {
                    usageCard
                        .padding(.bottom, 22)
                }

                Text(OffsendStrings.settingsLicenseDescription)
                    .font(.system(size: 11))
                    .foregroundColor(palette.textSub)
                    .padding(.bottom, 18)

                if plan == .pro {
                    proManagementSection
                } else if showExpiredTokenRecovery {
                    expiredTokenActions
                } else {
                    freeActivationSection
                }
            }
        }
        .onAppear {
            Task { await coordinator.licenseSettingsScreenDidAppear() }
        }
    }

    private var freePlanBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 16))
                .foregroundColor(palette.green)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(OffsendStrings.settingsLicenseFreeBannerTitle(OffsendStrings.appName))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(palette.text)
                Text(OffsendStrings.settingsLicenseFreeBannerSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.bg2)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border2, lineWidth: 1))
        )
    }

    private var planCardsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            planCardFree
                .frame(maxWidth: .infinity, minHeight: SettingsLicenseLayout.planCardsMinHeight, alignment: .topLeading)
            planCardPro
                .frame(maxWidth: .infinity, minHeight: SettingsLicenseLayout.planCardsMinHeight, alignment: .topLeading)
        }
    }

    private var proStatusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if billingPastDue, entitlement != .free {
                Text(OffsendStrings.settingsLicensePaymentIssueTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.text)
                Text(OffsendStrings.settingsLicensePaymentIssueSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSub)
            } else if entitlement == .free {
                Text(OffsendStrings.settingsLicenseInactiveTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.text)
                Text(OffsendStrings.settingsLicenseInactiveSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSub)
            } else {
                Text(OffsendStrings.settingsLicenseProActiveTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.text)
                Text(OffsendStrings.settingsLicenseProActiveSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSub)
            }
            if entitlement == .proGrace, let grace = graceDate {
                Text(OffsendStrings.settingsLicenseGraceSubtitle(AppLocalization.shortDate(grace)))
                    .font(.system(size: 11))
                    .foregroundColor(palette.textMuted)
            }
        }
    }

    private var expiredTokenHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(OffsendStrings.settingsLicenseInactiveTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(palette.text)
            Text(OffsendStrings.settingsLicenseInactiveSubtitle)
                .font(.system(size: 12))
                .foregroundColor(palette.textSub)
        }
    }

    private var proManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if billingPastDue || entitlement == .free {
                    OFCompactButton(title: OffsendStrings.settingsLicenseRenewPro, variant: .primary) {
                        Task { await coordinator.openProCheckout(prefillEmail: nil) }
                    }
                }
                if coordinator.canOpenLicenseBillingPortal() {
                    OFCompactButton(title: OffsendStrings.settingsLicenseManageLicense, variant: .ghost) {
                        Task { await coordinator.openBillingPortalFromLicense() }
                    }
                }
                OFCompactButton(title: OffsendStrings.settingsLicenseRefreshLicense, variant: .ghost) {
                    Task { await coordinator.refreshLicenseFromServer() }
                }
                OFCompactButton(title: OffsendStrings.settingsLicenseUseFree, variant: .ghost) {
                    coordinator.switchToFreePlan()
                }
            }
        }
    }

    private var expiredTokenActions: some View {
        HStack(spacing: 8) {
            OFCompactButton(title: OffsendStrings.settingsLicenseRenewPro, variant: .primary) {
                Task { await coordinator.openProCheckout(prefillEmail: nil) }
            }
            if coordinator.canOpenLicenseBillingPortal() {
                OFCompactButton(title: OffsendStrings.settingsLicenseManageLicense, variant: .ghost) {
                    Task { await coordinator.openBillingPortalFromLicense() }
                }
            }
            OFCompactButton(title: OffsendStrings.settingsLicenseUseFree, variant: .ghost) {
                coordinator.switchToFreePlan()
            }
        }
    }

    private var freeActivationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            OFSettingsGroup(
                title: coordinator.licensePricing.restoreGroupTitle ?? OffsendStrings.settingsLicenseAlreadyPurchasedTitle,
                hint: OffsendStrings.settingsLicenseAlreadyPurchasedSubtitle
            ) {
                OFSettingsRow(label: OffsendStrings.settingsEmail, hint: OffsendStrings.settingsLicenseEmailHint, alignTop: true) {
                    OFSettingsTextField(text: $activationEmail, prompt: Text(OffsendStrings.settingsEmail))
                }
                if activationStep == .checkEmail {
                    OFSettingsGroupDivider()
                    OFSettingsRow(label: OffsendStrings.settingsLicenseCodeLabel, hint: OffsendStrings.settingsLicenseCodeHint, alignTop: true) {
                        OFSettingsTextField(text: $activationCode, prompt: Text("000000"), monospaced: true)
                            .onChange(of: activationCode) { newValue in
                                let digits = newValue.filter(\.isNumber)
                                activationCode = String(digits.prefix(6))
                            }
                    }
                }
            }

            if activationStep == .checkEmail {
                VStack(alignment: .leading, spacing: 8) {
                    Text(OffsendStrings.settingsLicenseCheckEmailTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.text)
                        .padding(.top, 14)
                    Text(OffsendStrings.settingsLicenseCheckEmailBody(activationEmail))
                        .font(.system(size: 11.5))
                        .foregroundColor(palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !coordinator.licenseActivationDeviceLimit.isEmpty {
                deviceLimitCallout
                    .padding(.top, 12)
            }

            HStack(spacing: 8) {
                if activationStep == .collectEmail {
                    OFCompactButton(title: OffsendStrings.settingsLicenseSendActivationCode, variant: .primary) {
                        Task {
                            if await coordinator.requestLicenseActivationCode(email: activationEmail) {
                                activationStep = .checkEmail
                            }
                        }
                    }
                } else {
                    OFCompactButton(title: OffsendStrings.settingsLicenseVerifyCode, variant: .primary) {
                        Task {
                            await coordinator.verifyLicenseActivation(email: activationEmail, code: activationCode)
                            if coordinator.licenseState.plan == .pro {
                                activationCode = ""
                                activationStep = .collectEmail
                            }
                        }
                    }
                    OFCompactButton(title: OffsendStrings.settingsLicenseResendCode, variant: .ghost) {
                        Task { _ = await coordinator.requestLicenseActivationCode(email: activationEmail) }
                    }
                    OFCompactButton(title: OffsendStrings.settingsLicenseNoCodeBuyWithEmail, variant: .ghost) {
                        Task { await coordinator.openProCheckout(prefillEmail: activationEmail) }
                    }
                    OFCompactButton(title: OffsendStrings.settingsLicenseTryAnotherEmail, variant: .ghost) {
                        activationStep = .collectEmail
                        activationCode = ""
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var deviceLimitCallout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(OffsendStrings.settingsLicenseDeviceLimitTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(palette.text)
            ForEach(coordinator.licenseActivationDeviceLimit, id: \.activationId) { device in
                Text("• \(device.deviceName ?? device.activationId)")
                    .font(.system(size: 11))
                    .foregroundColor(palette.textSub)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(palette.bg2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border2, lineWidth: 1))
        )
    }

    private var planCardFree: some View {
        let active = plan == .free && !showExpiredTokenRecovery
        let accent = palette.green
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                planTierMark(label: OffsendStrings.settingsLicensePlanFree, color: accent)
                Spacer(minLength: 0)
                if active {
                    Text(OffsendStrings.settingsLicenseCurrentBadge)
                        .font(.system(size: 10, weight: .bold))
                        .kerning(0.4)
                        .foregroundColor(palette.greenText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.greenDim))
                }
            }
            Text(OffsendStrings.settingsLicensePriceFree)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(palette.text)
            Text(OffsendStrings.settingsLicenseForever)
                .font(.system(size: 11))
                .foregroundColor(palette.textSub)
            VStack(alignment: .leading, spacing: 6) {
                bullet(OffsendStrings.settingsLicenseFeatureFreeMasks(SettingsLicenseLayout.freeMonthlyLimit), color: accent)
                bullet(OffsendStrings.settingsLicenseFeatureFreeDetectors, color: accent)
                bullet(OffsendStrings.settingsLicenseFeatureFreeCustomDict, color: accent)
                bullet(OffsendStrings.settingsLicenseFeatureFreeTtl, color: accent)
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(active ? accent : palette.border2, lineWidth: active ? 2 : 1)
                )
        )
        .opacity(active ? 1 : 0.72)
    }

    private var showBuyInProCard: Bool {
        plan != .pro && !showExpiredTokenRecovery
    }

    private var planCardPro: some View {
        let pricing = coordinator.licensePricing
        let accent = palette.blue
        let macCap = pricing.defaultPlanDeviceLimit ?? SettingsLicenseLayout.proMarketingMacLimitFallback
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                planTierMark(label: OffsendStrings.settingsLicensePlanPro, color: accent)
                Spacer(minLength: 0)
                if plan == .pro {
                    Text(OffsendStrings.settingsLicenseCurrentBadge)
                        .font(.system(size: 10, weight: .bold))
                        .kerning(0.4)
                        .foregroundColor(palette.greenText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.greenDim))
                } else if showBuyInProCard {
                    Text(OffsendStrings.settingsLicenseRecommendedBadge)
                        .font(.system(size: 9.5, weight: .bold))
                        .kerning(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent))
                }
            }
            Group {
                if pricing.showsPrice, let line = pricing.primaryPriceDisplay, !line.isEmpty {
                    Text(line)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(palette.text)
                    Text(OffsendStrings.settingsLicenseProPurchaseFootnote)
                        .font(.system(size: 11))
                        .foregroundColor(palette.textSub)
                } else if let desc = pricing.defaultPlanDescription, !desc.isEmpty {
                    Text(pricing.productDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(palette.text)
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(palette.textSub)
                } else {
                    Text(pricing.productDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(palette.text)
                    if !pricing.subheadline.isEmpty {
                        Text(pricing.subheadline)
                            .font(.system(size: 11))
                            .foregroundColor(palette.textSub)
                    } else {
                        Text(OffsendStrings.settingsLicenseProPurchaseFootnote)
                            .font(.system(size: 11))
                            .foregroundColor(palette.textSub)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if pricing.featureBulletLabels.isEmpty {
                    bullet(OffsendStrings.settingsLicenseFeatureProUnlimited, color: accent)
                    bullet(OffsendStrings.settingsLicenseFeatureProSecretDetection, color: accent)
                    bullet(OffsendStrings.settingsLicenseFeatureProTtlMax, color: accent)
                    bullet(OffsendStrings.settingsLicenseFeatureProMacActivations(macCap), color: accent)
                } else {
                    ForEach(pricing.featureBulletLabels, id: \.self) { line in
                        bullet(line, color: accent)
                    }
                }
            }
            .padding(.top, 4)
            if showBuyInProCard {
                Spacer(minLength: 8)
                OFCompactButton(title: pricing.buyButtonTitle, variant: .primary) {
                    Task { await coordinator.openProCheckout(prefillEmail: nil) }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accent, lineWidth: 2)
                )
        )
    }

    private func planTierMark(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("•")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .foregroundColor(color)
        }
    }

    private func bullet(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundColor(palette.textSub)
        }
    }

    private var usageCard: some View {
        let used = coordinator.licenseState.maskedThisMonth
        let limit = SettingsLicenseLayout.freeMonthlyLimit
        let pct = min(Double(used) / Double(max(limit, 1)), 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(OffsendStrings.settingsLicenseUsageTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.text)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(used)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(palette.text)
                    Text("/ \(limit)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(palette.textSub)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(palette.bg3)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(pct > 0.85 ? palette.amber : palette.green)
                        .frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 6)
            Text(OffsendStrings.settingsLicenseUsageSubtitle)
                .font(.system(size: 11))
                .foregroundColor(palette.textMuted)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
        )
    }
}
