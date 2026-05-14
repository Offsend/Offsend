import AppUIKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @AppStorage(OFSettingsChromeAppearance.appStorageKey) private var chromeAppearanceRaw: String =
        OFSettingsChromeAppearance.auto.rawValue

    @State private var tab: SettingsSidebarTab = .general
    @State private var systemAppearanceRevision = 0

    private var chromeAppearance: OFSettingsChromeAppearance {
        OFSettingsChromeAppearance(rawValue: chromeAppearanceRaw) ?? .auto
    }

    private var palette: OFPalette {
        _ = systemAppearanceRevision
        return chromeAppearance.resolvedPalette()
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            mainPane
        }
        .frame(minWidth: 760, minHeight: 600)
        .background(palette.bg0)
        .environment(\.ofPalette, palette)
        .preferredColorScheme(chromeAppearance.preferredColorScheme)
        .tint(palette.blue)
        .ofRefreshOnSystemAppearanceChange($systemAppearanceRevision)
        .onChange(of: chromeAppearanceRaw) { _ in
            systemAppearanceRevision += 1
        }
        .onChange(of: coordinator.licensePostCheckoutFlowEmail) { newValue in
            if newValue != nil {
                tab = .license
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
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
                Text("\(OffsendStrings.settingsFooterLocalOnly) · \(OffsendStrings.appName)")
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

    private var mainPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: tab.sfSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(palette.text)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .general:
                        SettingsGeneralPanel()
                    case .hotkeys:
                        SettingsHotkeysPanel()
                    case .detection:
                        Group {
                            let tf = coordinator.tariffFeatures
                            if !tf.advancedDetectors && !tf.customDictionaries {
                                SettingsTariffUpsellOverlay {
                                    SettingsDetectionPanel(showsTeaserDespiteTariff: true)
                                }
                            } else {
                                SettingsDetectionPanel()
                            }
                        }
                    case .masking:
                        if coordinator.tariffFeatures.safePasteUnlimited {
                            SettingsMaskingPanel()
                        } else {
                            SettingsTariffUpsellOverlay {
                                SettingsMaskingPanel()
                            }
                        }
                    case .privacy:
                        VStack(alignment: .leading, spacing: 0) {
                            PrivacyView()
                                .padding(.bottom, 22)
                            SettingsPrivacyPanel()
                        }
                    case .license:
                        SettingsLicensePanel()
                    #if OFFSEND_INTERNAL
                    case .developer:
                        SettingsDeveloperPanel()
                    #endif
                    }
                }
                .environmentObject(coordinator)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
        }
    }
}

/// Stacks real settings UI under a light scrim and purchase banner (interaction blocked except CTA).
private struct SettingsTariffUpsellOverlay<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// Light enough to read content underneath; avoids Material obscuring the preview.
    private var scrimOpacity: Double {
        colorScheme == .dark ? 0.28 : 0.18
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .allowsHitTesting(false)
                .opacity(scrimOpacity)

            // Color.black.opacity(scrimOpacity)
            //     .frame(maxWidth: .infinity, maxHeight: .infinity)
            //     .allowsHitTesting(true)

            SettingsTariffUpsellBanner()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .allowsHitTesting(true)
        }
    }
}

private struct SettingsTariffUpsellBanner: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    var body: some View {
        let pricing = coordinator.licensePricing
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 15))
                    .foregroundColor(palette.blue)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(pricing.headline)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(palette.text)
                    if !pricing.subheadline.isEmpty {
                        Text(pricing.subheadline)
                            .font(.system(size: 12))
                            .foregroundColor(palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            OFSettingsGroupDivider()

            VStack(alignment: .leading, spacing: 8) {
               VStack(alignment: .leading, spacing: 8) {
                if pricing.featureBulletLabels.isEmpty {
                    tariffBullet(OffsendStrings.settingsLicenseFeatureProUnlimited)
                    tariffBullet(OffsendStrings.settingsLicenseFeatureProAdvanced)
                } else {
                    ForEach(pricing.featureBulletLabels, id: \.self) { line in
                        tariffBullet(line)
                    }
                }
                }

                OFCompactButton(title: pricing.buyButtonTitle, variant: .primary) {
                    Task { await coordinator.openProCheckout(prefillEmail: nil) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border2, lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
    }

    private func tariffBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(palette.blue)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundColor(palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
