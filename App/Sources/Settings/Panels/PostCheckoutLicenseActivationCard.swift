import AppUIKit
import SwiftUI

/// Post-web-checkout activation (deeplink `offsend://checkout/success`), aligned with `LicenseService.verifyActivationCode`.
struct PostCheckoutLicenseActivationCard: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    @State private var email: String = ""
    @State private var code: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.blue)
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(OffsendStrings.settingsLicensePostCheckoutTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(palette.text)

                        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(OffsendStrings.settingsLicensePostCheckoutSubtitleNoEmail)
                                .font(.system(size: 12))
                                .foregroundColor(palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(OffsendStrings.settingsLicensePostCheckoutSubtitleWithEmail(email))
                                .font(.system(size: 12))
                                .foregroundColor(palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        TextField(OffsendStrings.settingsEmail, text: $email)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(palette.bg2)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border2, lineWidth: 1))
                            )

                        SixDigitActivationCodeField(code: $code)
                            .padding(.top, 4)

                        if !coordinator.licenseActivationDeviceLimit.isEmpty {
                            deviceLimitCallout
                                .padding(.top, 8)
                        }

                        HStack(alignment: .center, spacing: 10) {
                            OFCompactButton(title: OffsendStrings.settingsLicenseTryAnotherEmail, variant: .outline) {
                                coordinator.clearLicensePostCheckoutFlow()
                                code = ""
                            }
                            OFCompactButton(title: OffsendStrings.settingsLicenseResendCode, variant: .ghost) {
                                Task { _ = await coordinator.requestLicenseActivationCode(email: effectiveEmail) }
                            }
                            OFCompactButton(title: OffsendStrings.settingsLicenseNoCodeBuyWithEmail, variant: .ghost) {
                                Task { await coordinator.openProCheckout(prefillEmail: effectiveEmail) }
                            }
                        }
                        .padding(.top, 6)

                        OFCompactButton(
                            title: OffsendStrings.settingsLicensePostCheckoutActivateThisMac,
                            variant: .primary,
                            small: false
                        ) {
                            Task {
                                await coordinator.verifyLicenseActivation(email: effectiveEmail, code: code)
                                if coordinator.licenseState.plan == .pro {
                                    code = ""
                                }
                            }
                        }
                        .padding(.top, 14)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border2, lineWidth: 1))
            )
            .onAppear {
                if let prefill = coordinator.licensePostCheckoutFlowEmail {
                    email = prefill
                }
            }
            .onChange(of: coordinator.licensePostCheckoutFlowEmail) { newValue in
                if let newValue {
                    email = newValue
                }
            }

            Text(OffsendStrings.settingsLicensePostCheckoutFootnote)
                .font(.system(size: 11))
                .foregroundColor(palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    private var effectiveEmail: String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return coordinator.licensePostCheckoutFlowEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
}

private struct SixDigitActivationCodeField: View {
    @Binding var code: String
    @FocusState private var focused: Bool
    @Environment(\.ofPalette) private var palette

    var body: some View {
        ZStack(alignment: .center) {
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.bg2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border2, lineWidth: 1))
                        Text(digitCharacter(at: index))
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundColor(palette.text)
                    }
                    .frame(width: 40, height: 48)
                }
            }
            TextField("", text: $code)
                .textFieldStyle(.plain)
                .font(.system(size: 2))
                .opacity(0.02)
                .frame(width: 12, height: 12)
                .focused($focused)
                .onChange(of: code) { newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    if digits != newValue {
                        code = digits
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focused = true
        }
    }

    private func digitCharacter(at index: Int) -> String {
        let digits = code.filter(\.isNumber)
        guard index < digits.count else { return "\u{2007}" }
        let i = digits.index(digits.startIndex, offsetBy: index)
        return String(digits[i])
    }
}
