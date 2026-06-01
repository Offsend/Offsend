import AppUIKit
import StorageCore
import SwiftUI

struct SettingsPrivacyPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    private var localEventsCount: Int {
        (try? coordinator.store.loadEvents())?.count ?? 0
    }

    var body: some View {
        let binder = SettingsCoordinatorBinder(coordinator: coordinator)
        VStack(alignment: .leading, spacing: 0) {
            summaryCard
                .padding(.bottom, 22)

            OFSettingsGroup(title: OffsendStrings.settingsPrivacySectionDiagnostics, hint: OffsendStrings.settingsPrivacyDiagnosticsLocalHint) {
                OFSettingsRow(label: OffsendStrings.settingsAnalyticsOptIn, hint: OffsendStrings.settingsAnalyticsOptInHint, alignTop: true) {
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
                    OFStatTile(
                        icon: "arrow.left.arrow.right",
                        label: OffsendStrings.settingsPrivacyStatMappings,
                        value: "\(coordinator.mappingSummaries.count)"
                    )
                    
                    OFCompactButton(
                        title: OffsendStrings.menuViewLocalMappings,
                        icon: "list.bullet.rectangle",
                        variant: .outline
                    ) {
                        coordinator.openPresentedWindow(id: "mappings")
                    }
                }
                
                OFStatTile(
                    icon: "clock.arrow.circlepath",
                    label: OffsendStrings.settingsPrivacyStatHistory,
                    value: "\(localEventsCount)"
                )
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

}
