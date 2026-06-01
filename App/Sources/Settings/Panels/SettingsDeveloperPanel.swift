#if DEBUG
import AppUIKit
import LicenseCore
import StorageCore
import SwiftUI

struct SettingsDeveloperPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OFSettingsGroup(
                title: OffsendStrings.settingsDeveloperLicenseServer,
                hint: OffsendStrings.settingsDeveloperLicenseServerHint
            ) {
                Picker("", selection: Binding(
                    get: { coordinator.debugLicenseAPIEnvironment },
                    set: { coordinator.debugSetLicenseAPIEnvironment($0) }
                )) {
                    ForEach(DebugLicenseAPIEnvironment.allCases) { env in
                        Text(licenseServerEnvironmentTitle(env)).tag(env)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 10)
                .frame(maxWidth: 420)

                Text(coordinator.debugLicenseAPIEnvironment.licenseConfiguration.apiBaseURL.absoluteString)
                    .padding(.bottom, 10)
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSub)
            }

            OFSettingsGroup(title: OffsendStrings.windowOnboarding) {
                OFSettingsRow(label: OffsendStrings.menuStartOnboarding, hint: nil) {
                    OFCompactButton(title: OffsendStrings.menuStartOnboarding, icon: "sparkles", variant: .outline) {
                        coordinator.openPresentedWindow(id: "onboarding") {
                            coordinator.requestOnboardingPresentation()
                        }
                    }
                }
                OFSettingsGroupDivider()
                OFSettingsRow(
                    label: OffsendStrings.settingsDeveloperResetSettingsFlags,
                    hint: OffsendStrings.settingsDeveloperResetSettingsFlagsHint
                ) {
                    OFCompactButton(
                        title: OffsendStrings.settingsDeveloperResetSettingsFlags,
                        icon: "arrow.counterclockwise",
                        variant: .outline
                    ) {
                        coordinator.debugResetSettingsFlags()
                    }
                }
            }

            OFSettingsGroup(
                title: OffsendStrings.settingsDeveloperSimulatedPlan,
                hint: OffsendStrings.settingsDeveloperSimulatedPlanHint
            ) {
                Picker("", selection: Binding(
                    get: { coordinator.licenseState.plan },
                    set: { coordinator.debugApplySimulatedLicensePlan($0) }
                )) {
                    Text(OffsendStrings.settingsPlanFree).tag(LicenseState.Plan.free)
                    Text(OffsendStrings.settingsPlanPro).tag(LicenseState.Plan.pro)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 10)
                .frame(maxWidth: 320)
            }

            OFSettingsGroup(
                title: OffsendStrings.settingsDeveloperTariffFeatures,
                hint: OffsendStrings.settingsDeveloperTariffFeaturesHint
            ) {
                ForEach(Array(LicenseTariffFeatureKey.allCases.enumerated()), id: \.element) { index, key in
                    if index > 0 {
                        OFSettingsGroupDivider()
                    }
                    OFSettingsRow(label: localizedFeatureLabel(key), hint: nil) {
                        OFToggle(isOn: tariffFeatureBinding(key))
                    }
                }
            }
        }
    }

    private func tariffFeatureBinding(_ key: LicenseTariffFeatureKey) -> Binding<Bool> {
        Binding(
            get: {
                switch key {
                case .safePasteUnlimited: coordinator.tariffFeatures.safePasteUnlimited
                case .advancedDetectors: coordinator.tariffFeatures.advancedDetectors
                case .customDictionaries: coordinator.tariffFeatures.customDictionaries
                case .workspaceAuditFull: coordinator.tariffFeatures.workspaceAuditFull
                case .workspaceAuditAutofix: coordinator.tariffFeatures.workspaceAuditAutofix
                }
            },
            set: { coordinator.debugSetTariffFeatureOverride(key, enabled: $0) }
        )
    }

    private func licenseServerEnvironmentTitle(_ env: DebugLicenseAPIEnvironment) -> String {
        switch env {
        case .production:
            OffsendStrings.settingsDeveloperLicenseServerProduction
        case .develop:
            OffsendStrings.settingsDeveloperLicenseServerDevelop
        }
    }

    private func localizedFeatureLabel(_ key: LicenseTariffFeatureKey) -> String {
        switch key {
        case .safePasteUnlimited:
            OffsendStrings.settingsDeveloperFeatureSafePasteUnlimited
        case .advancedDetectors:
            OffsendStrings.settingsDeveloperFeatureAdvancedDetectors
        case .customDictionaries:
            OffsendStrings.settingsDeveloperFeatureCustomDictionaries
        case .workspaceAuditFull:
            OffsendStrings.settingsDeveloperFeatureWorkspaceAuditFull
        case .workspaceAuditAutofix:
            OffsendStrings.settingsDeveloperFeatureWorkspaceAuditAutofix
        }
    }
}
#endif
