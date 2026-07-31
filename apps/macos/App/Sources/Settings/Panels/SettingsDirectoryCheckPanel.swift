import AppUIKit
import AppKit
import StorageCore
import SwiftUI
import WorkspacePolicyCore

struct SettingsDirectoryCheckPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    @State private var newSkippedDirectory: String = ""
    @State private var templateDraft: String = ""
    @State private var templateInitialized = false

    private var defaultTemplate: String {
        AIWorkspacePrivacyIgnoreTemplate.contents
    }

    private var trimmedNewSkippedDirectory: String {
        newSkippedDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddSkippedDirectory: Bool {
        !trimmedNewSkippedDirectory.isEmpty
    }

    private var canResetTemplate: Bool {
        coordinator.settings.directoryCheckCustomIgnoreTemplate != nil
    }

    var body: some View {
        let binder = SettingsCoordinatorBinder(coordinator: coordinator)
        VStack(alignment: .leading, spacing: 0) {
            summaryCard
                .padding(.bottom, 22)

            monitoredDirectoriesSection

            OFSettingsGroup(title: OffsendStrings.settingsDirectoryCheckSectionBehavior) {
                OFSettingsRow(
                    label: OffsendStrings.settingsDirectoryCheckNotifyOnDegrade,
                    hint: OffsendStrings.settingsDirectoryCheckNotifyOnDegradeHint,
                    alignTop: true
                ) {
                    OFToggle(isOn: binder.setting(\.directoryWatchNotifyOnDegrade))
                }

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
                    coordinator.recordDirectoryCheckOpened(source: "settings")
                    coordinator.openPrepareWindow(source: "settings_directory_check")
                }
            }

            HStack(alignment: .top, spacing: 10) {
                OFStatTile(
                    icon: "line.3.horizontal.decrease",
                    label: OffsendStrings.settingsDirectoryCheckStatRules,
                    value: "\(stats.rules)",
                    accessory: .none
                )
                OFStatTile(
                    icon: "gauge.medium",
                    label: OffsendStrings.settingsDirectoryCheckStatPatterns,
                    value: "\(stats.patterns)",
                    accessory: .none
                )
                OFStatTile(
                    icon: "folder",
                    label: OffsendStrings.settingsDirectoryCheckStatSkipped,
                    value: "\(stats.skipped)",
                    accessory: skippedAccessory(stats.skipped)
                )
                OFStatTile(
                    icon: "eye",
                    label: OffsendStrings.settingsDirectoryCheckMonitoredStatLabel,
                    value: "\(coordinator.settings.watchedDirectories.count)",
                    accessory: monitoredAccessory
                )
            }
            .fixedSize(horizontal: false, vertical: true)
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

    private func skippedAccessory(_ skipped: Int) -> OFStatTileAccessory {
        skipped > 0
            ? .caption(OffsendStrings.settingsDirectoryCheckStatSkippedCount(skipped))
            : .caption(OffsendStrings.settingsDirectoryCheckStatSkippedNone)
    }

    private var monitoredAccessory: OFStatTileAccessory {
        let count = coordinator.settings.watchedDirectories.count
        return coordinator.tariffFeatures.workspaceAuditFull
            ? .caption(OffsendStrings.settingsDirectoryCheckStatMonitoredPro(count))
            : .caption(OffsendStrings.settingsDirectoryCheckStatMonitoredFree(count, DirectoryWatchLimits.freeMaxRoots))
    }

    private func directoryCheckStats() -> (
        rules: Int,
        patterns: Int,
        skipped: Int
    ) {
        let baseConfig = coordinator.directoryCheckAuditConfiguration()
        let disabled = coordinator.settings.directoryCheckDisabledRuleIDs
        let activeRules = baseConfig.rules.filter { rule in
            rule.severity == .required || !disabled.contains(rule.id)
        }
        return (
            activeRules.count,
            baseConfig.sensitivePatterns.count,
            coordinator.settings.directoryCheckExtraSkippedDirectories.count
        )
    }

    // MARK: Monitored directories

    private var monitoredToggleBinding: Binding<Bool> {
        Binding(
            get: { coordinator.settings.directoryWatchEnabled },
            set: { newValue in
                coordinator.setDirectoryWatchEnabled(newValue)
            }
        )
    }

    private var monitoredDirectoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(OffsendStrings.settingsDirectoryCheckSectionMonitored.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(palette.textMuted)
                .padding(.leading, 2)

            Text(OffsendStrings.settingsDirectoryCheckMonitoredSectionHint)
                .font(.system(size: 12))
                .foregroundColor(palette.textSub)
                .padding(.leading, 2)
                .frame(maxWidth: 520, alignment: .leading)

            OFSettingsRow(
                label: OffsendStrings.settingsDirectoryCheckMonitoredToggle,
                hint: OffsendStrings.settingsDirectoryCheckMonitoredHint,
                alignTop: true
            ) {
                OFToggle(isOn: monitoredToggleBinding)
            }
            .padding(.bottom, 4)

            VStack(spacing: 0) {
                let entries = coordinator.settings.watchedDirectories
                if entries.isEmpty {
                    Text(OffsendStrings.settingsDirectoryCheckMonitoredEmpty)
                        .font(.system(size: 12))
                        .foregroundColor(palette.textSub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    ForEach(entries) { entry in
                        monitoredDirectoryRow(entry)
                        if entry.id != entries.last?.id {
                            OFSettingsGroupDivider()
                        }
                    }
                }

                Rectangle()
                    .fill(palette.border)
                    .frame(height: entries.isEmpty ? 0 : 1)

                HStack(spacing: 8) {
                    Spacer()
                    OFCompactButton(
                        title: OffsendStrings.settingsDirectoryCheckMonitoredAdd,
                        icon: "plus",
                        variant: .outline
                    ) {
                        addMonitoredDirectory()
                    }
                    .disabled(!coordinator.canAddMoreWatchedDirectories)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .opacity(coordinator.settings.directoryWatchEnabled ? 1 : 0.55)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
            )

            if !coordinator.tariffFeatures.workspaceAuditFull {
                Text(OffsendStrings.settingsDirectoryCheckMonitoredLimitFree)
                    .font(.system(size: 11))
                    .foregroundColor(palette.textMuted)
                    .padding(.leading, 2)
            }

            if !coordinator.canAddMoreWatchedDirectories {
                HStack(spacing: 8) {
                    Text(OffsendStrings.settingsDirectoryCheckMonitoredLimitReached)
                        .font(.system(size: 11))
                        .foregroundColor(palette.amberText)
                    Spacer()
                    OFCompactButton(
                        title: OffsendStrings.directoryCheckProUpsellCta,
                        icon: "crown.fill",
                        variant: .outline
                    ) {
                        Task { await coordinator.upgradeFromWatchLimit(source: "settings_banner") }
                    }
                }
                .padding(.leading, 2)
            }
        }
        .padding(.bottom, 24)
    }

    private func monitoredDirectoryRow(_ entry: WatchedDirectory) -> some View {
        let isUnavailable = coordinator.directoryWatchRuntime.unavailableWatchIDs.contains(entry.id)
        let isPaused = coordinator.isDirectoryWatchPaused(entry)
        let status = coordinator.directoryWatchRuntime.statusByWatchID[entry.id]
            ?? entry.lastStatus.flatMap(AIWorkspacePrivacyAuditStatus.init(rawValue:))
        let exposedPaths = coordinator.directoryWatchRuntime.lastResultByWatchID[entry.id]?
            .allExposedRelativePaths ?? []

        return HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundColor(palette.textMuted)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.resolvedPath ?? entry.displayName ?? OffsendStrings.settingsDirectoryCheckMonitoredUnavailable)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(isUnavailable || isPaused ? palette.textMuted : palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if isUnavailable {
                    Text(OffsendStrings.settingsDirectoryCheckMonitoredUnavailable)
                        .font(.system(size: 11))
                        .foregroundColor(palette.amberText)
                } else if isPaused {
                    Text(OffsendStrings.settingsDirectoryCheckMonitoredPaused)
                        .font(.system(size: 11))
                        .foregroundColor(palette.amberText)
                } else if let lastAuditAt = entry.lastAuditAt {
                    Text(relativeDate(lastAuditAt))
                        .font(.system(size: 11))
                        .foregroundColor(palette.textMuted)
                }

                if !isUnavailable,
                   !isPaused,
                   !exposedPaths.isEmpty,
                   let status,
                   watchStatusCountsAsAttention(status) {
                    Text(monitoredExposedSummary(exposedPaths))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(palette.amberText)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isUnavailable {
                OFCompactButton(
                    title: OffsendStrings.settingsDirectoryCheckMonitoredRePick,
                    icon: "arrow.triangle.2.circlepath",
                    variant: .outline
                ) {
                    rePickMonitoredDirectory(id: entry.id)
                }
            } else if let status, watchStatusCountsAsAttention(status) {
                watchStatusBadge(status)
            }

            Button {
                coordinator.removeWatchedDirectory(id: entry.id)
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
    }

    private func rePickMonitoredDirectory(id: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = OffsendStrings.settingsDirectoryCheckMonitoredRePick

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = coordinator.replaceWatchedDirectoryBookmark(id: id, url: url)
    }

    private func watchStatusCountsAsAttention(_ status: AIWorkspacePrivacyAuditStatus) -> Bool {
        WorkspaceWatchStatusDegrade.countsAsAttention(status)
    }

    private func watchStatusBadge(_ status: AIWorkspacePrivacyAuditStatus) -> some View {
        let title: String
        let textColor: Color
        let bgColor: Color
        switch status {
        case .pass:
            title = OffsendStrings.directoryCheckStatusPass
            textColor = palette.greenText
            bgColor = palette.greenDim
        case .warning:
            title = OffsendStrings.directoryCheckStatusWarning
            textColor = palette.amberText
            bgColor = palette.amberDim
        case .fail:
            title = OffsendStrings.directoryCheckStatusFail
            textColor = palette.redText
            bgColor = palette.redDim
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

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func monitoredExposedSummary(_ paths: [String]) -> String {
        let limit = 2
        if paths.count <= limit {
            return OffsendStrings.settingsDirectoryCheckMonitoredExposedFiles(paths.joined(separator: ", "))
        }
        let prefix = paths.prefix(limit).joined(separator: ", ")
        return OffsendStrings.settingsDirectoryCheckMonitoredExposedFiles(
            "\(prefix) +\(paths.count - limit) more"
        )
    }

    private func addMonitoredDirectory() {
        guard coordinator.canAddMoreWatchedDirectories else {
            Task { await coordinator.upgradeFromWatchLimit(source: "settings_add") }
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = OffsendStrings.settingsDirectoryCheckMonitoredAdd

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !coordinator.addWatchedDirectory(url: url) {
            Task { await coordinator.upgradeFromWatchLimit(source: "settings_add_failed") }
        }
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
                    .disabled(!canAddSkippedDirectory)
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
        let disabledBinding = ruleDisabledBinding(for: rule.id)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(rule.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(palette.text)
                    severityBadge(severity: rule.severity)
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

    // MARK: Ignore template

    private var ignoreTemplateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(OffsendStrings.settingsDirectoryCheckSectionTemplate.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(palette.textMuted)
                Spacer()
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
                    .onChange(of: templateDraft) { newValue in
                        guard templateInitialized else { return }
                        saveTemplateDraft(newValue)
                    }

                HStack(spacing: 8) {
                    Spacer()
                    OFCompactButton(
                        title: OffsendStrings.settingsDirectoryCheckTemplateReset,
                        icon: "arrow.uturn.backward",
                        variant: .outline
                    ) {
                        resetTemplate()
                    }
                    .disabled(!canResetTemplate)
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
