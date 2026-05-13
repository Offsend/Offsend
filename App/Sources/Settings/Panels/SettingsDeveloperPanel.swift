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
                OFSettingsRow(label: LicenseTariffFeatureKey.safePasteUnlimited.rawValue, hint: nil) {
                    Text(tf.safePasteUnlimited ? "ON" : "OFF")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(tf.safePasteUnlimited ? .green : .secondary)
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: LicenseTariffFeatureKey.advancedDetectors.rawValue, hint: nil) {
                    Text(tf.advancedDetectors ? "ON" : "OFF")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(tf.advancedDetectors ? .green : .secondary)
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: LicenseTariffFeatureKey.customDictionaries.rawValue, hint: nil) {
                    Text(tf.customDictionaries ? "ON" : "OFF")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(tf.customDictionaries ? .green : .secondary)
                }
            }
        }
    }
}
#endif
