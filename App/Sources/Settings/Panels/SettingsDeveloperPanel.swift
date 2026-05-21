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
                let tf = coordinator.tariffFeatures
                OFSettingsRow(label: localizedFeatureLabel(.safePasteUnlimited), hint: nil) {
                    Text(tf.safePasteUnlimited ? OffsendStrings.commonOn : OffsendStrings.commonOff)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(tf.safePasteUnlimited ? .green : .secondary)
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: localizedFeatureLabel(.advancedDetectors), hint: nil) {
                    Text(tf.advancedDetectors ? OffsendStrings.commonOn : OffsendStrings.commonOff)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(tf.advancedDetectors ? .green : .secondary)
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: localizedFeatureLabel(.customDictionaries), hint: nil) {
                    Text(tf.customDictionaries ? OffsendStrings.commonOn : OffsendStrings.commonOff)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(tf.customDictionaries ? .green : .secondary)
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: localizedFeatureLabel(.workspaceAuditFull), hint: nil) {
                    Text(tf.workspaceAuditFull ? OffsendStrings.commonOn : OffsendStrings.commonOff)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(tf.workspaceAuditFull ? .green : .secondary)
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: localizedFeatureLabel(.workspaceAuditAutofix), hint: nil) {
                    Text(tf.workspaceAuditAutofix ? OffsendStrings.commonOn : OffsendStrings.commonOff)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(tf.workspaceAuditAutofix ? .green : .secondary)
                }
            }
        }
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
