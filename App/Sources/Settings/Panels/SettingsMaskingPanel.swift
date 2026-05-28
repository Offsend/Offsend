import AppUIKit
import MaskingCore
import StorageCore
import SwiftUI

struct SettingsMaskingPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    var body: some View {
        let binder = SettingsCoordinatorBinder(coordinator: coordinator)
        let extendedMappingTTLAllowed = coordinator.allowsExtendedMappingTTL
        let mappingTTLOptions = MappingTTL.allowedOptions(extendedTTLAllowed: extendedMappingTTLAllowed)
        VStack(alignment: .leading, spacing: 0) {
            maskingPreviewBlock
                .padding(.bottom, 22)

            OFSettingsGroup(title: OffsendStrings.settingsMaskingSectionMapping) {
                OFSettingsRow(label: OffsendStrings.settingsMappingTTL, hint: nil) {
                    OFSelectMenu(
                        selection: binder.setting(\.mappingTTL),
                        options: mappingTTLOptions.map {
                            OFSelectOption(value: $0, label: AppLocalization.mappingTTLName($0))
                        }
                    )
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: OffsendStrings.settingsRestoreBehavior, hint: nil) {
                    OFSelectMenu(
                        selection: binder.setting(\.restoreBehavior),
                        options: RestoreBehavior.allCases.map {
                            OFSelectOption(value: $0, label: AppLocalization.restoreBehaviorName($0))
                        }
                    )
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: OffsendStrings.settingsPreserveOriginalClipboard, hint: nil) {
                    OFToggle(isOn: binder.setting(\.preserveOriginalClipboard))
                }
            }

            OFSettingsGroup(title: OffsendStrings.settingsMaskingSectionRisky) {
                OFSettingsRow(
                    label: OffsendStrings.settingsAllowPasteOriginalForCriticalSecrets,
                    hint: nil,
                    alignTop: true
                ) {
                    OFToggle(isOn: binder.setting(\.allowPasteOriginalForCriticalSecrets))
                }
            }
        }
        .onAppear {
            coordinator.syncMappingTTLToTariff()
        }
        .onChange(of: coordinator.licenseState) { _ in
            coordinator.syncMappingTTLToTariff()
        }
    }

    private var maskingPreviewBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.blue)
                Text(OffsendStrings.settingsMaskingPreviewTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundColor(palette.textMuted)
            }
            OFFlowLayout(spacing: 2) {
                Text("Email ")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(palette.textSub)
                OFPlaceholderChip(text: "{{EMAIL_1}}")
                Text(" re invoice ")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(palette.textSub)
                OFPlaceholderChip(text: "{{INVOICE_1}}")
                Text(" for ")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(palette.textSub)
                OFPlaceholderChip(text: "{{AMOUNT_1}}")
                Text(".")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(palette.textSub)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(palette.bg0))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
        )
    }
}
