import AppUIKit
import StorageCore
import SwiftUI

struct SettingsPrivacyPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette
    @Environment(\.openWindow) private var openWindow

    private var localEventsCount: Int {
        (try? coordinator.store.loadEvents())?.count ?? 0
    }

    var body: some View {
        let binder = SettingsCoordinatorBinder(coordinator: coordinator)
        VStack(alignment: .leading, spacing: 0) {
            summaryCard
                .padding(.bottom, 22)

            OFSettingsGroup(title: OffsendStrings.settingsPrivacySectionDiagnostics, hint: OffsendStrings.settingsPrivacyDiagnosticsAnalyticsHint) {
                OFSettingsRow(label: OffsendStrings.settingsAnalyticsOptIn, hint: nil, alignTop: true) {
                    OFToggle(isOn: binder.setting(\.analyticsOptIn))
                }
            }

            OFSettingsGroup(title: OffsendStrings.settingsTabPrivacy) {
                OFSettingsRow(label: OffsendStrings.settingsClearAllLocalMappings, hint: nil, alignTop: true) {
                    OFCompactButton(title: OffsendStrings.settingsClearAllLocalMappings, icon: "trash", variant: .outline) {
                        coordinator.clearAllMappings()
                    }
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: OffsendStrings.settingsClearLocalHistory, hint: nil, alignTop: true) {
                    OFCompactButton(title: OffsendStrings.settingsClearLocalHistory, icon: "trash", variant: .outline) {
                        coordinator.clearLocalHistory()
                    }
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: OffsendStrings.settingsExportPrivacyReport, hint: nil, alignTop: true) {
                    OFCompactButton(title: OffsendStrings.settingsExportPrivacyReport, icon: "square.and.arrow.up", variant: .outline) {
                        coordinator.clipboardService.writeString(coordinator.exportPrivacyReport())
                    }
                }
            }

            if !coordinator.lastStatusMessage.isEmpty, coordinator.lastStatusMessage != OffsendStrings.statusReady {
                Text(coordinator.lastStatusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(palette.textMuted)
                    .padding(.top, 8)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(palette.greenDim)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.green)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(OffsendStrings.settingsPrivacySummaryTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.text)
                    Text(OffsendStrings.settingsPrivacySummarySubtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(palette.textSub)
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    statTile(label: OffsendStrings.settingsPrivacyStatMappings, value: "\(coordinator.mappingSummaries.count)", sub: "")
                    OFCompactButton(
                        title: OffsendStrings.menuViewLocalMappings,
                        icon: "list.bullet.rectangle",
                        variant: .outline
                    ) {
                        openWindow(id: "mappings")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                statTile(label: OffsendStrings.settingsPrivacyStatHistory, value: "\(localEventsCount)", sub: "")
                // statTile(label: OffsendStrings.settingsPrivacyStatCloud, value: "0", sub: OffsendStrings.settingsPrivacyStatAlways)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [palette.greenDim, palette.card],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border, lineWidth: 1))
        )
    }

    private func statTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.6)
                .foregroundColor(palette.textMuted)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(palette.text)
            if !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.textSub)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.bg0)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
        )
    }
}
