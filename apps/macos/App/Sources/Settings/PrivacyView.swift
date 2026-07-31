import AppUIKit
import SwiftUI

struct PrivacyView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, OFSpacing.lg)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "cpu", text: OffsendStrings.privacyItemLocalProcessing)
                featureRow(icon: "clipboard", text: OffsendStrings.privacyItemClipboard)
                featureRow(icon: "icloud.slash", text: OffsendStrings.privacyItemNeverUploaded)
                featureRow(icon: "key.fill", text: OffsendStrings.privacyItemEncryptedMappings)
                featureRow(icon: "chart.bar", text: OffsendStrings.privacyItemAnalytics)
                featureRow(icon: "eye.slash", text: OffsendStrings.privacyItemMonitoringOff)
            }
            .padding(.bottom, OFSpacing.xl)

            // Text(OffsendStrings.privacyCurrentLocalState)
            //     .font(.system(size: 13, weight: .semibold))
            //     .foregroundColor(palette.text)
            //     .padding(.bottom, 10)

            // reportCard
            //     .padding(.bottom, OFSpacing.lg)

            privacyFooterStrip
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(palette.greenDim)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.green)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(OffsendStrings.privacyTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(palette.text)

                Text(OffsendStrings.onboardingPrivacySubtitle)
                    .font(.system(size: 14))
                    .foregroundColor(palette.textSub)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(palette.blue)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reportCard: some View {
        Text(coordinator.exportPrivacyReport())
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(palette.text)
            .textSelection(.enabled)
            .padding(OFSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bg2)
            .cornerRadius(OFRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.md)
                    .stroke(palette.border, lineWidth: 1)
            )
    }

    private var privacyFooterStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(palette.green)
                .frame(width: 5, height: 5)

            Text(OffsendStrings.onboardingFooterPrivacy)
                .font(.system(size: 10))
                .foregroundColor(palette.textMuted)

            Spacer()
        }
        .padding(.horizontal, OFSpacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bg0)
        .cornerRadius(OFRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.sm)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}
