import AppUIKit
import StorageCore
import SwiftUI
import WorkspacePolicyCore

struct SettingsDirectoryCheckPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette
    @Environment(\.openWindow) private var openWindow

    @State private var newSkippedDirectory: String = ""
    @State private var templateDraft: String = ""
    @State private var templateInitialized = false

    private var defaultTemplate: String {
        AIWorkspacePrivacyIgnoreTemplate.contents
    }

    private var canEditTemplate: Bool {
        coordinator.tariffFeatures.workspaceAuditFull
    }

    var body: some View {
        let binder = SettingsCoordinatorBinder(coordinator: coordinator)
        VStack(alignment: .leading, spacing: 0) {
            summaryCard
                .padding(.bottom, 22)

            OFSettingsGroup(title: OffsendStrings.settingsDirectoryCheckSectionBehavior) {
                OFSettingsRow(
                    label: OffsendStrings.settingsDirectoryCheckConfirmFix,
                    hint: OffsendStrings.settingsDirectoryCheckConfirmFixHint,
                    alignTop: true
                ) {
                    OFToggle(isOn: binder.setting(\.directoryCheckConfirmFix))
                }
            }

            skippedDirectoriesSection
            toolRulesSection
            sensitivePatternsSection
            ignoreTemplateSection
        }
        .onAppear { initializeTemplateDraftIfNeeded() }
        .onChange(of: coordinator.settings.directoryCheckCustomIgnoreTemplate) { _ in
            initializeTemplateDraftIfNeeded(force: true)
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        let stats = directoryCheckStats()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(palette.blueDim)
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.blue)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(OffsendStrings.settingsDirectoryCheckSummaryTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.text)
                    Text(OffsendStrings.settingsDirectoryCheckSummarySubtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                OFCompactButton(
                    title: OffsendStrings.settingsDirectoryCheckOpenWindow,
                    icon: "folder",
                    variant: .primary
                ) {
                    openWindow(id: "directory-check")
                }
            }

            HStack(spacing: 10) {
                statTile(
                    label: OffsendStrings.settingsDirectoryCheckStatRules,
                    value: "\(stats.rules)",
                    proExtra: stats.rulesProExtra
                )
                statTile(
                    label: OffsendStrings.settingsDirectoryCheckStatPatterns,
                    value: "\(stats.patterns)",
                    proExtra: stats.patternsProExtra
                )
                statTile(
                    label: OffsendStrings.settingsDirectoryCheckStatSkipped,
                    value: "\(stats.skipped)",
                    proExtra: 0
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [palette.blueDim, palette.card],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border, lineWidth: 1))
        )
    }

    private func statTile(label: String, value: String, proExtra: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.6)
                .foregroundColor(palette.textMuted)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(palette.text)
            if proExtra > 0 {
                Text(OffsendStrings.settingsDirectoryCheckStatProExtra(proExtra))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(palette.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.bg0)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
        )
    }

    private func directoryCheckStats() -> (
        rules: Int,
        patterns: Int,
        skipped: Int,
        rulesProExtra: Int,
        patternsProExtra: Int
    ) {
        let isPro = coordinator.tariffFeatures.workspaceAuditFull
        let baseConfig: AIWorkspacePrivacyAuditConfiguration = isPro ? .default : .freeTier
        let disabled = coordinator.settings.directoryCheckDisabledRuleIDs
        let activeRules = baseConfig.rules.filter { rule in
            rule.severity == .required || !disabled.contains(rule.id)
        }
        let rulesProExtra = isPro ? 0 : max(0, AIWorkspacePrivacyRule.defaultRules.count - baseConfig.rules.count)
        let patternsProExtra = isPro ? 0 : max(0, AIWorkspaceSensitivePattern.defaultPatterns.count - baseConfig.sensitivePatterns.count)
        return (
            activeRules.count,
            baseConfig.sensitivePatterns.count,
            coordinator.settings.directoryCheckExtraSkippedDirectories.count,
            rulesProExtra,
            patternsProExtra
        )
    }

    // MARK: Skipped directories

    private var skippedDirectoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(OffsendStrings.settingsDirectoryCheckSectionSkipped.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(palette.textMuted)
                .padding(.leading, 2)

            Text(OffsendStrings.settingsDirectoryCheckSkippedHint)
                .font(.system(size: 12))
                .foregroundColor(palette.textSub)
                .padding(.leading, 2)
                .frame(maxWidth: 520, alignment: .leading)

            VStack(spacing: 0) {
                let names = coordinator.settings.directoryCheckExtraSkippedDirectories
                if names.isEmpty {
                    Text(OffsendStrings.settingsDirectoryCheckSkippedEmpty)
                        .font(.system(size: 12))
                        .foregroundColor(palette.textSub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                                .foregroundColor(palette.textMuted)
                                .frame(width: 16)
                            Text(name)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundColor(palette.text)
                            Spacer()
                            Button {
                                removeSkippedDirectory(at: idx)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(palette.textMuted)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        if idx < names.count - 1 {
                            OFSettingsGroupDivider()
                        }
                    }
                }

                Rectangle()
                    .fill(palette.border)
                    .frame(height: names.isEmpty ? 0 : 1)

                HStack(spacing: 8) {
                    TextField(OffsendStrings.settingsDirectoryCheckSkippedPlaceholder, text: $newSkippedDirectory)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundColor(palette.text)
                        .onSubmit(addSkippedDirectory)
                    OFCompactButton(
                        title: OffsendStrings.settingsDirectoryCheckSkippedAdd,
                        icon: "plus",
                        variant: .outline
                    ) {
                        addSkippedDirectory()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
            )

            Text(OffsendStrings.settingsDirectoryCheckSkippedNoEffectNote)
                .font(.system(size: 11))
                .foregroundColor(palette.textMuted)
                .padding(.leading, 2)
        }
        .padding(.bottom, 24)
    }

    private func addSkippedDirectory() {
        let trimmed = newSkippedDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !coordinator.settings.directoryCheckExtraSkippedDirectories.contains(where: {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else {
            newSkippedDirectory = ""
            return
        }
        coordinator.settings.directoryCheckExtraSkippedDirectories.append(trimmed)
        coordinator.saveSettings()
        newSkippedDirectory = ""
    }

    private func removeSkippedDirectory(at index: Int) {
        guard coordinator.settings.directoryCheckExtraSkippedDirectories.indices.contains(index) else { return }
        coordinator.settings.directoryCheckExtraSkippedDirectories.remove(at: index)
        coordinator.saveSettings()
    }

    // MARK: Tool rules

    private var toolRulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(OffsendStrings.settingsDirectoryCheckSectionTools.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(palette.textMuted)
                .padding(.leading, 2)

            Text(OffsendStrings.settingsDirectoryCheckToolsHint)
                .font(.system(size: 12))
                .foregroundColor(palette.textSub)
                .padding(.leading, 2)
                .frame(maxWidth: 520, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(AIWorkspacePrivacyRule.defaultRules.enumerated()), id: \.element.id) { idx, rule in
                    toolRuleRow(rule: rule)
                    if idx < AIWorkspacePrivacyRule.defaultRules.count - 1 {
                        OFSettingsGroupDivider()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
            )
        }
        .padding(.bottom, 24)
    }

    private func toolRuleRow(rule: AIWorkspacePrivacyRule) -> some View {
        let isRequired = rule.severity == .required
        let isLockedByTariff = !isInRequiredFreeSet(rule) && !coordinator.tariffFeatures.workspaceAuditFull
        let disabledBinding = ruleDisabledBinding(for: rule.id)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(rule.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(palette.text)
                    severityBadge(severity: rule.severity)
                    if isLockedByTariff {
                        scopeBadge(text: OffsendStrings.settingsDirectoryCheckScopePro, color: palette.amber)
                    }
                }
                Text(rule.toolName)
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.textSub)
            }
            Spacer()

            if isRequired {
                Text(OffsendStrings.settingsDirectoryCheckRequiredLocked)
                    .font(.system(size: 11))
                    .foregroundColor(palette.textMuted)
            } else if isLockedByTariff {
                Text(OffsendStrings.settingsDirectoryCheckProLocked)
                    .font(.system(size: 11))
                    .foregroundColor(palette.amberText)
            } else {
                OFToggle(isOn: Binding(
                    get: { !disabledBinding.wrappedValue },
                    set: { disabledBinding.wrappedValue = !$0 }
                ))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func isInRequiredFreeSet(_ rule: AIWorkspacePrivacyRule) -> Bool {
        AIWorkspacePrivacyAuditConfiguration.freeTier.rules.contains(where: { $0.id == rule.id })
    }

    private func ruleDisabledBinding(for ruleID: String) -> Binding<Bool> {
        Binding(
            get: { coordinator.settings.directoryCheckDisabledRuleIDs.contains(ruleID) },
            set: { newValue in
                var set = coordinator.settings.directoryCheckDisabledRuleIDs
                if newValue {
                    set.insert(ruleID)
                } else {
                    set.remove(ruleID)
                }
                coordinator.settings.directoryCheckDisabledRuleIDs = set
                coordinator.saveSettings()
            }
        )
    }

    // MARK: Sensitive patterns (read-only)

    private var sensitivePatternsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(OffsendStrings.settingsDirectoryCheckSectionPatterns.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(palette.textMuted)
                .padding(.leading, 2)

            Text(OffsendStrings.settingsDirectoryCheckPatternsHint)
                .font(.system(size: 12))
                .foregroundColor(palette.textSub)
                .padding(.leading, 2)
                .frame(maxWidth: 520, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(AIWorkspaceSensitivePattern.defaultPatterns.enumerated()), id: \.element.id) { idx, pattern in
                    patternRow(pattern: pattern)
                    if idx < AIWorkspaceSensitivePattern.defaultPatterns.count - 1 {
                        OFSettingsGroupDivider()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
            )
        }
        .padding(.bottom, 24)
    }

    private func patternRow(pattern: AIWorkspaceSensitivePattern) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(pattern.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.text)
                severityBadge(severity: pattern.severity)
            }
            Text(pattern.acceptedPatterns.prefix(4).joined(separator: ", "))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(palette.textSub)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Ignore template (Pro)

    private var ignoreTemplateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(OffsendStrings.settingsDirectoryCheckSectionTemplate.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(palette.textMuted)
                Spacer()
                if !canEditTemplate {
                    Text(OffsendStrings.settingsDirectoryCheckScopePro)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(palette.amberText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(palette.amberDim)
                        .cornerRadius(6)
                }
            }
            .padding(.leading, 2)

            Text(OffsendStrings.settingsDirectoryCheckTemplateHint)
                .font(.system(size: 12))
                .foregroundColor(palette.textSub)
                .padding(.leading, 2)
                .frame(maxWidth: 520, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $templateDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(palette.text)
                    .scrollContentBackground(.hidden)
                    .background(palette.bg0)
                    .frame(minHeight: 180, maxHeight: 320)
                    .disabled(!canEditTemplate)
                    .onChange(of: templateDraft) { newValue in
                        guard canEditTemplate, templateInitialized else { return }
                        saveTemplateDraft(newValue)
                    }

                HStack(spacing: 8) {
                    if !canEditTemplate {
                        Text(OffsendStrings.settingsDirectoryCheckTemplateLocked)
                            .font(.system(size: 11))
                            .foregroundColor(palette.textMuted)
                    }
                    Spacer()
                    OFCompactButton(
                        title: OffsendStrings.settingsDirectoryCheckTemplateReset,
                        icon: "arrow.uturn.backward",
                        variant: .outline
                    ) {
                        resetTemplate()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
            )
        }
        .padding(.bottom, 24)
    }

    private func initializeTemplateDraftIfNeeded(force: Bool = false) {
        guard force || !templateInitialized else { return }
        templateDraft = coordinator.settings.directoryCheckCustomIgnoreTemplate ?? defaultTemplate
        templateInitialized = true
    }

    private func saveTemplateDraft(_ text: String) {
        let normalized = text == defaultTemplate ? nil : text
        coordinator.settings.directoryCheckCustomIgnoreTemplate = normalized
        coordinator.saveSettings()
    }

    private func resetTemplate() {
        templateDraft = defaultTemplate
        coordinator.settings.directoryCheckCustomIgnoreTemplate = nil
        coordinator.saveSettings()
    }

    // MARK: Badges

    private func severityBadge(severity: AIWorkspacePrivacyRuleSeverity) -> some View {
        let title: String
        let textColor: Color
        let bgColor: Color
        switch severity {
        case .required:
            title = OffsendStrings.settingsDirectoryCheckSeverityRequired
            textColor = palette.redText
            bgColor = palette.redDim
        case .recommended:
            title = OffsendStrings.settingsDirectoryCheckSeverityRecommended
            textColor = palette.amberText
            bgColor = palette.amberDim
        case .informational:
            title = OffsendStrings.settingsDirectoryCheckSeverityInformational
            textColor = palette.blueText
            bgColor = palette.blueDim
        }
        return Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgColor)
            .cornerRadius(4)
    }

    private func scopeBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .cornerRadius(4)
    }
}
