import AppUIKit
import DetectionCore
import LicenseCore
import SwiftUI

enum DetectorSeverityBadge {
    case medium
    case critical

    func accent(_ p: OFPalette) -> Color {
        switch self {
        case .medium:
            return p.amber
        case .critical:
            return p.red
        }
    }

    func dim(_ p: OFPalette) -> Color {
        switch self {
        case .medium:
            return p.amberDim
        case .critical:
            return p.redDim
        }
    }

    func text(_ p: OFPalette) -> Color {
        switch self {
        case .medium:
            return p.amberText
        case .critical:
            return p.redText
        }
    }

    var localizedLabel: String {
        switch self {
        case .medium:
            return OffsendStrings.settingsDetectionSeverityMedium
        case .critical:
            return OffsendStrings.settingsDetectionSeverityCritical
        }
    }
}

enum DetectorGroupKind: Hashable {
    case personal
    case business
    case secrets
    case custom

    var title: String {
        switch self {
        case .personal:
            return OffsendStrings.settingsDetectionGroupPersonal
        case .business:
            return OffsendStrings.settingsDetectionGroupBusiness
        case .secrets:
            return OffsendStrings.settingsDetectionGroupSecrets
        case .custom:
            return OffsendStrings.settingsDetectionGroupCustom
        }
    }
}

struct DetectorGroupModel {
    let kind: DetectorGroupKind
    let severity: DetectorSeverityBadge
    let types: [SensitiveEntityType]
}

enum SettingsDetectionCatalog {
    static let groups: [DetectorGroupModel] = [
        DetectorGroupModel(
            kind: .personal,
            severity: .medium,
            types: [.email, .phone, .ipAddress, .url]
        ),
        DetectorGroupModel(
            kind: .business,
            severity: .medium,
            types: [.money, .internalDomain, .contractId, .invoiceId, .orderId, .creditCardLike, .iban]
        ),
        DetectorGroupModel(
            kind: .secrets,
            severity: .critical,
            types: [
                .apiKeyGeneric,
                .openAIAPIKey,
                .awsAccessKeyId,
                .githubToken,
                .slackToken,
                .stripeKey,
                .jwt,
                .privateKey,
                .sshPrivateKey,
                .databaseURLWithPassword,
                .bearerToken,
                .highEntropyString,
            ]
        ),
        DetectorGroupModel(
            kind: .custom,
            severity: .medium,
            types: [.customClient, .customCompany, .customProject, .customSensitiveTerm, .customInternalDomain]
        ),
    ]

    static var coveredTypes: Set<SensitiveEntityType> {
        Set(groups.flatMap(\.types))
    }
}

struct SettingsDetectionPanel: View {
    /// When `true`, renders search, all detector groups, and custom dictionaries as if Pro features were enabled.
    /// Used under the tariff upsell overlay so users can preview the full Pro UI (interaction remains blocked by the overlay).
    var showsTeaserDespiteTariff: Bool = false

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    @State private var search = ""
    @State private var newDictionaryKind: CustomDictionaryKind = .client
    @State private var newDictionaryValue = ""

    var body: some View {
        let binder = SettingsCoordinatorBinder(coordinator: coordinator)
        let tf = coordinator.tariffFeatures
        let advancedOn = showsTeaserDespiteTariff || tf.advancedDetectors
        let customOn = showsTeaserDespiteTariff || tf.customDictionaries
        let groups = visibleDetectorGroups(advancedDetectors: advancedOn, customDictionaries: customOn)
        VStack(alignment: .leading, spacing: 0) {
            if advancedOn {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(palette.textMuted)
                        TextField(OffsendStrings.settingsDetectionSearchPlaceholder, text: $search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(palette.text)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.bg2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
                    )

                    let enabledCount = coordinator.settings.enabledDetectors.count
                    let total = SensitiveEntityType.allCases.count
                    HStack(spacing: 6) {
                        Text("\(enabledCount)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(palette.text)
                        Text(OffsendStrings.settingsDetectionActiveSummary(total))
                            .font(.system(size: 11.5))
                            .foregroundColor(palette.textSub)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.bg2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
                    )
                }
                .padding(.bottom, 18)
            }

            ForEach(groups, id: \.kind) { group in
                let filteredTypes = group.types.filter { type in
                    search.isEmpty
                        || AppLocalization.sensitiveEntityTypeName(type)
                        .lowercased()
                        .contains(search.lowercased())
                }
                Group {
                    if !filteredTypes.isEmpty {
                        detectorGroupSection(title: group.kind.title, severity: group.severity, types: filteredTypes, binder: binder)
                            .padding(.bottom, 18)
                    }
                }
            }

            if customOn {
                customDictionariesSection(binder: binder)
            }
        }
        .onAppear {
            assert(
                SettingsDetectionCatalog.coveredTypes == Set(SensitiveEntityType.allCases),
                "Update SettingsDetectionCatalog.groups for new SensitiveEntityType cases"
            )
        }
    }

    private func visibleDetectorGroups(advancedDetectors: Bool, customDictionaries: Bool) -> [DetectorGroupModel] {
        guard advancedDetectors else { return [] }
        return SettingsDetectionCatalog.groups.filter { group in
            if group.kind == .custom {
                return customDictionaries
            }
            return true
        }
    }

    private func detectorGroupSection(
        title: String,
        severity: DetectorSeverityBadge,
        types: [SensitiveEntityType],
        binder: SettingsCoordinatorBinder
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(palette.textMuted)
                Text(severity.localizedLabel.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .kerning(0.5)
                    .foregroundColor(severity.text(palette))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(severity.dim(palette)))
            }
            .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(types.enumerated()), id: \.element) { idx, type in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(severity.accent(palette))
                            .frame(width: 5, height: 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.sensitiveEntityTypeName(type))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(palette.text)
                            Text(detectorExample(type))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(palette.textMuted)
                        }
                        Spacer()
                        OFToggle(isOn: detectorBinding(type, binder: binder), size: 18)
                    }
                    .padding(.vertical, 10)
                    if idx < types.count - 1 {
                        OFSettingsGroupDivider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
            )
        }
    }

    private func detectorBinding(_ type: SensitiveEntityType, binder _: SettingsCoordinatorBinder) -> Binding<Bool> {
        Binding(
            get: { coordinator.settings.enabledDetectors.contains(type) },
            set: { enabled in
                if enabled {
                    coordinator.settings.enabledDetectors.insert(type)
                } else {
                    coordinator.settings.enabledDetectors.remove(type)
                }
                coordinator.saveSettings()
            }
        )
    }

    private func detectorExample(_ type: SensitiveEntityType) -> String {
        switch type {
        case .email:
            return "name@domain.com"
        case .phone:
            return "+1 · national formats"
        case .ipAddress:
            return "IPv4 / IPv6"
        case .url:
            return "https://…"
        case .money:
            return "$1,200 · €500"
        case .internalDomain, .customInternalDomain:
            return "*.corp.example.com"
        case .contractId:
            return "CN-4812"
        case .invoiceId:
            return "INV-…"
        case .orderId:
            return "ORD-…"
        case .creditCardLike:
            return "4242…"
        case .iban:
            return "DE89…"
        case .apiKeyGeneric, .bearerToken:
            return "Authorization headers"
        case .openAIAPIKey:
            return "sk-…"
        case .awsAccessKeyId:
            return "AKIA…"
        case .githubToken:
            return "ghp_…"
        case .slackToken:
            return "xox…"
        case .stripeKey:
            return "sk_live_…"
        case .jwt:
            return "eyJhbGciOiJ…"
        case .privateKey, .sshPrivateKey:
            return "-----BEGIN … KEY-----"
        case .databaseURLWithPassword:
            return "postgres://…"
        case .highEntropyString:
            return "Long random secret-like strings"
        case .customClient, .customCompany, .customProject, .customSensitiveTerm:
            return "Dictionary match"
        }
    }

    private func customDictionariesSection(binder _: SettingsCoordinatorBinder) -> some View {
        OFSettingsGroup(title: OffsendStrings.settingsCustomDictionaries, hint: OffsendStrings.settingsDictionaryPlaceholder) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    OFSelectMenu(
                        selection: $newDictionaryKind,
                        options: CustomDictionaryKind.allCases.map {
                            OFSelectOption(value: $0, label: AppLocalization.customDictionaryKindName($0))
                        },
                        width: 130
                    )
                    TextField(OffsendStrings.settingsDictionaryPlaceholder, text: $newDictionaryValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(palette.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(palette.bg2)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.border2, lineWidth: 1))
                        )
                        .onSubmit { addDictionaryItem() }
                    OFCompactButton(title: OffsendStrings.settingsAdd, icon: "plus", variant: .outline) {
                        addDictionaryItem()
                    }
                    .disabled(newDictionaryValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                OFFlexibleWrap(spacing: 6) {
                    ForEach(coordinator.customDictionaries) { item in
                        HStack(spacing: 6) {
                            Text(AppLocalization.customDictionaryKindName(item.kind).uppercased())
                                .font(.system(size: 9.5, weight: .bold))
                                .kerning(0.4)
                                .foregroundColor(palette.textMuted)
                            Text(item.value)
                                .font(.system(size: 11.5))
                                .foregroundColor(palette.text)
                            Button {
                                coordinator.customDictionaries.removeAll { $0.id == item.id }
                                coordinator.saveCustomDictionaries()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(palette.textMuted)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(palette.bg2)
                                .overlay(Capsule().stroke(palette.border, lineWidth: 1))
                        )
                    }
                }
            }
            .padding(.vertical, 14)
        }
    }

    private func addDictionaryItem() {
        let trimmed = newDictionaryValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coordinator.customDictionaries.append(CustomDictionaryItem(kind: newDictionaryKind, value: trimmed))
        newDictionaryValue = ""
        coordinator.saveCustomDictionaries()
    }
}
