import AppUIKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @AppStorage(OFSettingsChromeAppearance.appStorageKey) private var chromeAppearanceRaw: String =
        OFSettingsChromeAppearance.auto.rawValue

    @State private var tab: SettingsSidebarTab = .general

    private var chromeAppearance: OFSettingsChromeAppearance {
        OFSettingsChromeAppearance(rawValue: chromeAppearanceRaw) ?? .auto
    }

    var body: some View {
        OFChromeShell { palette in
            HStack(spacing: 0) {
                sidebar(palette: palette)
                mainPane(palette: palette)
            }
            .frame(minWidth: 820, minHeight: 600)
            .background(palette.bg0)
        }
        .onChange(of: coordinator.licensePostCheckoutFlowEmail) { newValue in
            if newValue != nil {
                tab = .license
            }
        }
        .onChange(of: coordinator.pendingSettingsTab) { newValue in
            if let newValue {
                tab = newValue
                coordinator.pendingSettingsTab = nil
            }
        }
        .dismissOnWindowCloseButton()
    }

    // MARK: Sidebar

    private func sidebar(palette: OFPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.black, .black.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    OffsendAsset.Images.logo.swiftUIImage
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.white)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(OffsendStrings.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.text)
                    Text(
                        "v \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")"
                    )
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(palette.textMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)
                .padding(.horizontal, 14)

            VStack(spacing: 1) {
                ForEach(SettingsSidebarTab.allCases) { tb in
                    let active = tb == tab
                    Button {
                        tab = tb
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tb.sfSymbol)
                                .font(.system(size: 13))
                                .foregroundColor(active ? palette.blue : palette.textSub)
                                .frame(width: 16)
                            Text(tb.title)
                                .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                                .foregroundColor(active ? palette.text : palette.textSub)
                            if tb == .ai {
                                aiPreviewBadge(palette: palette, compact: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(active ? palette.bg3 : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(palette.green)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().fill(palette.green.opacity(0.25)).frame(width: 12, height: 12))
                Text(OffsendStrings.settingsFooterLocalOnly)
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.textSub)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1),
                alignment: .top
            )
        }
        .frame(width: 188)
        .background(palette.bg1)
        .overlay(
            Rectangle()
                .fill(palette.border)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    // MARK: Main pane

    private var showsTariffUpsellBanner: Bool {
        switch tab {
        case .detection:
            return !coordinator.tariffFeatures.customDictionaries
        default:
            return false
        }
    }

    private var tariffUpsellMessage: String {
        switch tab {
        case .detection:
            return OffsendStrings.settingsTariffUpsellDetectionMessage
        default:
            return OffsendStrings.settingsTariffUpsellMessage
        }
    }

    private func mainPane(palette: OFPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: tab.sfSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.text)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(tab.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(palette.text)
                        if tab == .ai {
                            aiPreviewBadge(palette: palette)
                        }
                    }
                    Text(tab.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(palette.textMuted)
                }
                Spacer()
                OFSegmentedControl(
                    selection: Binding(
                        get: { chromeAppearance },
                        set: { chromeAppearanceRaw = $0.rawValue }
                    ),
                    options: [
                        OFSegmentedOption(value: .light, label: OffsendStrings.settingsThemeLight),
                        OFSegmentedOption(value: .dark, label: OffsendStrings.settingsThemeDark),
                        OFSegmentedOption(value: .auto, label: OffsendStrings.settingsThemeAuto),
                    ]
                )
            }
            .padding(.horizontal, 24)
            .frame(height: 56)
            .overlay(
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1),
                alignment: .bottom
            )

            if showsTariffUpsellBanner {
                SettingsTariffUpsellBanner(message: tariffUpsellMessage)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .general:
                        SettingsGeneralPanel()
                    case .hotkeys:
                        SettingsHotkeysPanel()
                    case .detection:
                        SettingsDetectionPanel()
                    case .ai:
                        SettingsAIPanel()
                    case .masking:
                        SettingsMaskingPanel()
                    case .privacy:
                        VStack(alignment: .leading, spacing: 0) {
                            PrivacyView()
                                .padding(.bottom, 22)
                            SettingsPrivacyPanel()
                        }
                    case .directoryCheck:
                        SettingsDirectoryCheckPanel()
                    case .license:
                        SettingsLicensePanel()
                    #if DEBUG
                    case .developer:
                        SettingsDeveloperPanel()
                    #endif
                    }
                }
                .environmentObject(coordinator)
                .padding(.horizontal, 24)
                .padding(.top, showsTariffUpsellBanner ? 16 : 22)
                .padding(.bottom, scrollContentBottomPadding)
            }
            .frame(maxHeight: .infinity)

            if tab == .ai, coordinator.aiModelDownloadProgress != nil {
                aiDownloadProgressBar(palette: palette)
            }
        }
    }

    private var scrollContentBottomPadding: CGFloat {
        var padding: CGFloat = 24
        if tab == .ai, coordinator.aiModelDownloadProgress != nil {
            padding += SettingsAIDownloadProgressBanner.pinnedBarHeight
        }
        return padding
    }

    private func aiPreviewBadge(palette: OFPalette, compact: Bool = false) -> some View {
        Text(OffsendStrings.settingsTabAiPreviewBadge)
            .font(.system(size: compact ? 9 : 9.5, weight: .bold))
            .kerning(0.5)
            .foregroundColor(palette.amberText)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 1 : 2)
            .background(Capsule().fill(palette.amberDim))
    }

    @ViewBuilder
    private func aiDownloadProgressBar(palette: OFPalette) -> some View {
        if let progress = coordinator.aiModelDownloadProgress {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)

                SettingsAIDownloadProgressBanner(progress: progress)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .frame(height: SettingsAIDownloadProgressBanner.pinnedBarHeight)
        }
    }
}

private struct SettingsTariffUpsellBanner: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 14))
                .foregroundColor(palette.blue)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(palette.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            OFCompactButton(title: coordinator.licensePricing.buyButtonTitle, variant: .primary) {
                Task { await coordinator.openProCheckout(prefillEmail: nil) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border2, lineWidth: 1))
                .allowsHitTesting(false)
        )
    }
}
