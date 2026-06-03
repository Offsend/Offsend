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
        VStack(alignment: .leading, spacing: 0) {
            documentSanitizeCard
                .padding(.bottom, 22)

            maskingPreviewBlock
                .padding(.bottom, 22)

            OFSettingsGroup(title: OffsendStrings.settingsMaskingSectionMapping) {
                mappingTTLRow(
                    binder: binder,
                    extendedMappingTTLAllowed: extendedMappingTTLAllowed
                )
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

    private func mappingTTLRow(
        binder: SettingsCoordinatorBinder,
        extendedMappingTTLAllowed: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(OffsendStrings.settingsMappingTTL)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(palette.text)
                    if !extendedMappingTTLAllowed {
                        proScopeBadge
                    }
                }
                if !extendedMappingTTLAllowed {
                    Text(OffsendStrings.settingsMaskingMappingTTLProHint)
                        .font(.system(size: 11.5))
                        .foregroundColor(palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            OFSelectMenu(
                selection: binder.setting(\.mappingTTL),
                options: mappingTTLOptions(extendedMappingTTLAllowed: extendedMappingTTLAllowed)
            )
        }
        .padding(.vertical, 12)
    }

    private func mappingTTLOptions(extendedMappingTTLAllowed: Bool) -> [OFSelectOption<MappingTTL>] {
        MappingTTL.allCases.map { ttl in
            let isProOption = ttl != .oneHour
            let isEnabled = extendedMappingTTLAllowed || !isProOption
            return OFSelectOption(
                value: ttl,
                label: AppLocalization.mappingTTLName(ttl),
                detail: isProOption && !extendedMappingTTLAllowed
                    ? OffsendStrings.settingsDirectoryCheckScopePro
                    : nil,
                isEnabled: isEnabled
            )
        }
    }

    private var proScopeBadge: some View {
        Text(OffsendStrings.settingsDirectoryCheckScopePro)
            .font(.system(size: 9.5, weight: .bold))
            .kerning(0.5)
            .foregroundColor(palette.amberText)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(palette.amberDim))
    }

    private var documentSanitizeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(palette.blueDim)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.blue)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(OffsendStrings.settingsDocumentSanitizeSummaryTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.text)
                    Text(OffsendStrings.settingsDocumentSanitizeSummarySubtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                OFCompactButton(
                    title: OffsendStrings.settingsDocumentSanitizeOpenWindow,
                    icon: "doc",
                    variant: .primary
                ) {
                    coordinator.recordDocumentSanitizeOpened(source: "settings")
                    coordinator.openPresentedWindow(id: "document-sanitize")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
        )
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
