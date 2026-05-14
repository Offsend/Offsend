#if DEBUG
import AppUIKit
import LicenseCore
import StorageCore
import SwiftUI

struct SettingsDeveloperPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            }
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
        }
    }
}
#endif
