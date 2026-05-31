import AppKit
import AppUIKit
import LicenseCore
import StorageCore
import SwiftUI
import UniformTypeIdentifiers
import WorkspacePolicyCore

struct DirectoryCheckView: View {
    let directoryWindowPath: String?

    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var selectedDirectory: URL?
    @State private var auditResult: AIWorkspacePrivacyAuditResult?
    @State private var isDropTargeted = false
    @State private var fixMessage: String?
    @State private var selectedFixItemIDs: Set<String> = []
    @State private var isAuditing = false
    @State private var isApplyingFix = false
    @State private var auditToken = UUID()
    @State private var isShowingCachedWatchStatus = false
    @State private var auditDelta: AIWorkspacePrivacyAuditDelta?
    @State private var activeWork: Task<Void, Never>?

    private var isBusy: Bool { isAuditing || isApplyingFix }

    private var effectiveSelectedDirectory: URL? {
        selectedDirectory
    }

    private var isBootstrapPending: Bool {
        directoryWindowPath != nil && auditResult == nil && selectedDirectory == nil
    }

    private var showsWorkingOverlay: Bool {
        isBusy || isBootstrapPending
    }

    private enum Layout {
        static let windowWidth: CGFloat = 640
        static let emptyStateHeight: CGFloat = 320
        static let resultStateHeight: CGFloat = 860
        static let freeBannerExtra: CGFloat = 88
    }

    private struct AuditIssueCounts {
        let fail: Int
        let warn: Int
        let ok: Int

        var totalIssues: Int { fail + warn }
    }

    private var auditConfiguration: AIWorkspacePrivacyAuditConfiguration {
        coordinator.directoryCheckAuditConfiguration()
    }

    private var directoryCheckAuditSettings: DirectoryCheckAuditSettings {
        DirectoryCheckAuditSettings(
            disabledRuleIDs: coordinator.settings.directoryCheckDisabledRuleIDs,
            extraSkippedDirectories: coordinator.settings.directoryCheckExtraSkippedDirectories,
            customIgnoreTemplate: coordinator.settings.directoryCheckCustomIgnoreTemplate
        )
    }

    private var canAutofix: Bool {
        coordinator.licenseState.plan == .pro && coordinator.tariffFeatures.workspaceAuditAutofix
    }

    var body: some View {
        let features = coordinator.tariffFeatures
        let showsFooter = auditResult.map { shouldShowPinnedFooter(for: $0) } ?? false
        let windowHeight = preferredWindowHeight(
            showsFreeBanner: !features.workspaceAuditFull,
            hasSelectedDirectory: effectiveSelectedDirectory != nil
        )
        let windowSize = NSSize(width: Layout.windowWidth, height: windowHeight)

        VStack(spacing: 0) {
            header
                .padding(.horizontal, OFSpacing.xxl)
                .padding(.top, OFSpacing.xl)
                .padding(.bottom, OFSpacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: OFSpacing.lg) {
                    if !features.workspaceAuditFull {
                        freeScopeNote
                    }

                    if effectiveSelectedDirectory == nil {
                        emptyDropZone
                    } else if let auditResult {
                        folderAndWatchCard(auditResult)

                        if let fixMessage {
                            fixResultBanner(fixMessage)
                        }

                        if isShowingCachedWatchStatus {
                            cachedWatchStatusSection(for: auditResult)
                        } else {
                            if let auditDelta {
                                auditChangesSection(auditDelta)
                            }

                            if showsProtectedState(auditResult) {
                                protectedBanner(for: auditResult)
                            } else {
                                issueSummaryBar(auditResult)
                                auditFindingsContent(auditResult)
                            }
                        }

                        if !features.workspaceAuditFull {
                            proUpsellCard
                        }
                    }
                }
                .padding(.horizontal, OFSpacing.xxl)
                .padding(.bottom, OFSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsFooter, let auditResult {
                pinnedFooter(for: auditResult)
            }
        }
        .frame(
            width: Layout.windowWidth,
            height: windowHeight,
            alignment: .top
        )
        .background(Color.ofBg1)
        .background(DirectoryCheckWindowSizer(size: windowSize))
        .overlay {
            if showsWorkingOverlay {
                workingOverlay
            }
        }
        .disabled(showsWorkingOverlay)
        .onAppear {
            prefillDirectoryFromPasteboard()
            bootstrapFromWindowPathIfNeeded()
        }
        .onChange(of: directoryWindowPath) { _ in
            bootstrapFromWindowPathIfNeeded()
        }
        .onDisappear {
            activeWork?.cancel()
            activeWork = nil
        }
        .onChange(of: coordinator.tariffFeatures) { _ in
            guard let selectedDirectory else { return }
            audit(directoryURL: selectedDirectory)
        }
        .onChange(of: directoryCheckAuditSettings) { _ in
            guard let selectedDirectory else { return }
            audit(directoryURL: selectedDirectory)
        }
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.12)
            VStack(spacing: OFSpacing.md) {
                ProgressView()
                    .controlSize(.regular)
                Text(isApplyingFix ? OffsendStrings.directoryCheckApplyingFix : OffsendStrings.directoryCheckAuditing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.ofText)
            }
            .padding(OFSpacing.xl)
            .background(Color.ofBg2)
            .cornerRadius(OFRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.lg)
                    .stroke(Color.ofBorder, lineWidth: 1)
            )
        }
    }

    private func preferredWindowHeight(
        showsFreeBanner: Bool,
        hasSelectedDirectory: Bool
    ) -> CGFloat {
        guard hasSelectedDirectory else {
            var height = Layout.emptyStateHeight
            if showsFreeBanner {
                height += Layout.freeBannerExtra
            }
            return height
        }

        return Layout.resultStateHeight
    }

    private func shouldShowPinnedFooter(for result: AIWorkspacePrivacyAuditResult) -> Bool {
        canFix(result) && !fixItems(for: result).isEmpty
    }

    private func isFreeApplicableFixItem(_ item: AIWorkspacePrivacyFixItem) -> Bool {
        switch item.kind {
        case .ruleFile:
            return AIWorkspacePrivacyAuditConfiguration.freeFixableRuleIDs.contains(item.id)
        case .sensitivePattern:
            return true
        }
    }

    /// A fix the current tier cannot apply. Pro can apply everything; Free is limited to
    /// the two common ignore files (sensitive patterns fold into those files).
    private func isProOnlyFixItem(_ item: AIWorkspacePrivacyFixItem) -> Bool {
        guard !canAutofix else { return false }
        return !isFreeApplicableFixItem(item)
    }

    private func selectionRequiresPro(for result: AIWorkspacePrivacyAuditResult) -> Bool {
        guard !canAutofix else { return false }
        return fixItems(for: result).contains {
            selectedFixItemIDs.contains($0.id) && isProOnlyFixItem($0)
        }
    }

    private func showsProtectedState(_ result: AIWorkspacePrivacyAuditResult) -> Bool {
        result.status == .pass
            && result.errors.isEmpty
            && result.missingRequiredRules.isEmpty
            && result.missingSensitivePatterns.isEmpty
            && result.missingRecommendedRules.isEmpty
    }

    private func issueCounts(for result: AIWorkspacePrivacyAuditResult) -> AuditIssueCounts {
        let fail = result.missingRequiredRules.count
            + result.errors.count
            + result.missingSensitivePatterns.filter { $0.pattern.severity == .required }.count
        let warn = result.missingRecommendedRules.count
            + result.missingSensitivePatterns.filter { $0.pattern.severity != .required }.count
        let ok = result.ruleFindings.filter(\.isSatisfied).count
            + result.sensitivePatternFindings.filter(\.isSatisfied).count
        return AuditIssueCounts(fail: fail, warn: warn, ok: ok)
    }

    private func totalPrivacyRules(for result: AIWorkspacePrivacyAuditResult) -> Int {
        result.ruleFindings.count + result.sensitivePatternFindings.count
    }

    private func displayPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private var isWatchingSelectedDirectory: Bool {
        guard let selectedDirectory,
              let entry = watchedEntryForSelection else {
            return false
        }
        return coordinator.settings.directoryWatchEnabled
            && !coordinator.isDirectoryWatchPaused(entry)
    }

    private var watchToggleBinding: Binding<Bool> {
        Binding(
            get: { isWatchingSelectedDirectory },
            set: { toggleWatchForSelectedDirectory(enabled: $0) }
        )
    }

    private func toggleWatchForSelectedDirectory(enabled: Bool) {
        guard let selectedDirectory else { return }
        if enabled {
            if coordinator.addWatchedDirectory(url: selectedDirectory, source: "directory_check") {
                return
            }
            Task { await coordinator.upgradeFromWatchLimit(source: "directory_check") }
        } else if let entry = watchedEntryForSelection {
            coordinator.removeWatchedDirectory(id: entry.id)
        }
    }

    private func fixItems(for result: AIWorkspacePrivacyAuditResult) -> [AIWorkspacePrivacyFixItem] {
        AIWorkspacePrivacyFixPlanner.fixItems(for: result, configuration: auditConfiguration)
    }

    private func defaultFixItemSelection(for result: AIWorkspacePrivacyAuditResult) -> Set<String> {
        let items = fixItems(for: result)
        let applicableItems = canAutofix ? items : items.filter { isFreeApplicableFixItem($0) }
        let selection = AIWorkspacePrivacyFixPlanner.defaultSelection(for: applicableItems, result: result)
        return selection.ruleIDs.union(selection.patternIDs)
    }

    private var allFixItemsSelected: Bool {
        guard let auditResult else { return false }
        let items = fixItems(for: auditResult)
        return !items.isEmpty && selectedFixItemIDs.count == items.count
    }

    private var hasSelectedFixItems: Bool {
        !selectedFixItemIDs.isEmpty
    }

    private func canApplyFixSelection(for result: AIWorkspacePrivacyAuditResult) -> Bool {
        guard hasSelectedFixItems else { return false }
        let selection = fixSelection(for: result)
        if selection.ruleIDs.isEmpty && !selection.patternIDs.isEmpty {
            return false
        }
        if !selection.patternIDs.isEmpty {
            return !patternTargetPaths(for: result, selection: selection).isEmpty
        }
        return true
    }

    private func hasSelectedPolicyFiles(for result: AIWorkspacePrivacyAuditResult) -> Bool {
        !fixSelection(for: result).ruleIDs.isEmpty
    }

    private func clearPatternSelection(for result: AIWorkspacePrivacyAuditResult) {
        for item in fixItems(for: result) {
            if case .sensitivePattern = item.kind {
                selectedFixItemIDs.remove(item.id)
            }
        }
    }

    private func patternTargetPaths(
        for result: AIWorkspacePrivacyAuditResult,
        selection: AIWorkspacePrivacyFixSelection
    ) -> [String] {
        AIWorkspacePrivacyFixPlanner.patternTargetRelativePaths(
            for: result,
            configuration: auditConfiguration,
            selection: selection
        )
    }

    private var hasSelectedPatternsWithoutTargets: Bool {
        guard let auditResult else { return false }
        return !hasSelectedPolicyFiles(for: auditResult)
            && fixItems(for: auditResult).contains { if case .sensitivePattern = $0.kind { return true }; return false }
    }

    private func fixSelection(for result: AIWorkspacePrivacyAuditResult) -> AIWorkspacePrivacyFixSelection {
        AIWorkspacePrivacyFixPlanner.selection(
            from: selectedFixItemIDs,
            in: fixItems(for: result)
        )
    }

    private var freeScopeNote: some View {
        HStack(alignment: .top, spacing: OFSpacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.ofBlue)
                .padding(.top, 1)

            Text(OffsendStrings.directoryCheckFreeScopeNote)
                .font(.system(size: 12))
                .foregroundColor(.ofTextSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ofBlueDim)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBlue.opacity(0.25), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            OFIconTile(
                systemName: "folder.badge.gearshape",
                tint: .ofBlue,
                size: 44,
                iconSize: 18,
                glow: true
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(OffsendStrings.directoryCheckTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.ofText)

                Text(OffsendStrings.directoryCheckSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            OFButton(title: OffsendStrings.directoryCheckChooseFolder, variant: .outline, icon: "folder", small: true) {
                chooseDirectory()
            }
            .disabled(isBusy)
        }
    }

    private var emptyDropZone: some View {
        OFDropZone(
            title: OffsendStrings.directoryCheckDropTitle,
            hint: OffsendStrings.directoryCheckDropHint,
            isTargeted: isDropTargeted
        ) {
            guard !isBusy else { return }
            chooseDirectory()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            guard !isBusy else { return false }
            return handleDrop(providers)
        }
    }

    private func folderAndWatchCard(_ result: AIWorkspacePrivacyAuditResult) -> some View {
        OFCardGroup {
            HStack(alignment: .center, spacing: OFSpacing.md) {
                OFIconTile(systemName: "folder.fill", tint: .ofTextMuted, size: 32, iconSize: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.directoryURL.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ofText)
                        .lineLimit(1)

                    Text(displayPath(for: result.directoryURL))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.ofTextSub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                OFStatusCapsule(
                    style: statusBadgeStyle(for: result.status),
                    title: statusTitle(for: result.status)
                )
            }
            .padding(.horizontal, OFSpacing.md)
            .padding(.vertical, 12)

            OFCardGroupDivider()

            OFCardRow(
                icon: "eye.fill",
                iconTint: .ofBlue,
                title: OffsendStrings.directoryCheckWatchInBackground,
                subtitle: watchSubtitle,
                subtitleTint: isWatchingSelectedDirectory ? .ofGreenText : .ofTextSub,
                highlighted: isWatchingSelectedDirectory
            ) {
                OFToggle(isOn: watchToggleBinding)
            }
        }
    }

    private var watchSubtitle: String {
        if isWatchingSelectedDirectory {
            return OffsendStrings.directoryCheckWatchOnHint
        }
        return OffsendStrings.directoryCheckWatchOffHint
    }

    private func issueSummaryBar(_ result: AIWorkspacePrivacyAuditResult) -> some View {
        let counts = issueCounts(for: result)

        return HStack(spacing: OFSpacing.sm) {
            Text(OffsendStrings.directoryCheckIssuesFound(counts.totalIssues))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.ofText)

            if counts.fail > 0 {
                OFCountPill(count: counts.fail, style: .fail)
            }
            if counts.warn > 0 {
                OFCountPill(count: counts.warn, style: .warn)
            }
            if counts.ok > 0 {
                OFCountPill(count: counts.ok, style: .ok)
            }

            Spacer(minLength: 0)

            OFButton(title: OffsendStrings.directoryCheckRefreshAudit, variant: .outline, icon: "arrow.clockwise", small: true) {
                audit(directoryURL: result.directoryURL)
            }
            .disabled(isBusy)
        }
    }

    private func protectedBanner(for result: AIWorkspacePrivacyAuditResult) -> some View {
        let ruleCount = totalPrivacyRules(for: result)
        let subtitle = isWatchingSelectedDirectory
            ? OffsendStrings.directoryCheckProtectedSubtitle(ruleCount)
            : OffsendStrings.directoryCheckProtectedSubtitleNoWatch(ruleCount)

        return OFSemanticBanner(
            style: .success,
            icon: "checkmark.shield",
            title: OffsendStrings.directoryCheckProtectedTitle,
            subtitle: subtitle
        )
    }

    private func fixResultBanner(_ message: String) -> some View {
        OFSemanticBanner(
            style: .info,
            icon: "info.circle.fill",
            title: OffsendStrings.directoryCheckFixResultTitle,
            subtitle: message
        )
    }

    @ViewBuilder
    private func pinnedFooter(for result: AIWorkspacePrivacyAuditResult) -> some View {
        if selectionRequiresPro(for: result) {
            OFPinnedActionFooter(
                statusText: OffsendStrings.directoryCheckProSelectionNote,
                buttonTitle: OffsendStrings.directoryCheckBuyPro,
                buttonIcon: "crown.fill",
                buttonDisabled: isBusy
            ) {
                Task { await coordinator.openProCheckout(prefillEmail: nil) }
            }
        } else {
            let selectedCount = selectedFixItemIDs.count
            OFPinnedActionFooter(
                statusText: OffsendStrings.directoryCheckFixesSelected(selectedCount),
                buttonTitle: selectedCount == 1
                    ? OffsendStrings.directoryCheckApplyFix
                    : OffsendStrings.directoryCheckApplyFixes(selectedCount),
                buttonDisabled: isBusy || !canApplyFixSelection(for: result)
            ) {
                fix(result)
            }
        }
    }

    private func auditFindingsContent(
        _ result: AIWorkspacePrivacyAuditResult
    ) -> some View {
        let showsFixSelection = canFix(result)

        return VStack(alignment: .leading, spacing: OFSpacing.md) {
            if !result.errors.isEmpty {
                findingsCard(title: OffsendStrings.directoryCheckSectionErrors) {
                    ForEach(Array(result.errors.enumerated()), id: \.element.id) { index, error in
                        if index > 0 { OFCardGroupDivider() }
                        readOnlyFindingRow(title: error.message, subtitle: error.id, tag: .fail)
                    }
                }
            }

            if showsFixSelection {
                suggestedFixesCard(for: result)
            } else {
                if !result.missingRequiredRules.isEmpty {
                    findingsCard(title: OffsendStrings.directoryCheckSectionRequired) {
                        ForEach(Array(result.missingRequiredRules.enumerated()), id: \.element.id) { index, finding in
                            if index > 0 { OFCardGroupDivider() }
                            readOnlyFindingRow(
                                title: finding.rule.title,
                                subtitle: ruleFindingSubtitle(for: finding),
                                tag: .fail,
                                toolName: finding.rule.toolName
                            )
                        }
                    }
                }

                if !result.missingSensitivePatterns.isEmpty {
                    findingsCard(title: OffsendStrings.directoryCheckSectionSensitivePatterns) {
                        ForEach(Array(result.missingSensitivePatterns.enumerated()), id: \.element.id) { index, finding in
                            if index > 0 { OFCardGroupDivider() }
                            readOnlyFindingRow(
                                title: finding.pattern.title,
                                subtitle: sensitivePatternSubtitle(for: finding),
                                tag: severityTag(finding.pattern.severity)
                            )
                        }
                    }
                }

                if !result.missingRecommendedRules.isEmpty {
                    findingsCard(title: OffsendStrings.directoryCheckSectionRecommended) {
                        ForEach(Array(result.missingRecommendedRules.enumerated()), id: \.element.id) { index, finding in
                            if index > 0 { OFCardGroupDivider() }
                            readOnlyFindingRow(
                                title: finding.rule.title,
                                subtitle: ruleFindingSubtitle(for: finding),
                                tag: .warn,
                                toolName: finding.rule.toolName
                            )
                        }
                    }
                }
            }
        }
    }

    private func suggestedFixesCard(for result: AIWorkspacePrivacyAuditResult) -> some View {
        let items = fixItems(for: result)

        return VStack(alignment: .leading, spacing: OFSpacing.sm) {
            HStack {
                Text(OffsendStrings.directoryCheckSuggestedFixes.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(.ofTextMuted)

                Spacer()

                Button {
                    if allFixItemsSelected {
                        selectedFixItemIDs.removeAll()
                    } else {
                        selectedFixItemIDs = Set(items.map(\.id))
                    }
                } label: {
                    Text(allFixItemsSelected
                        ? OffsendStrings.directoryCheckFixSelectionDeselectAll
                        : OffsendStrings.directoryCheckFixSelectionSelectAll)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ofBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            OFCardGroup {
                ForEach(Array(fixRowItemIDs(for: result).enumerated()), id: \.element) { index, itemID in
                    if index > 0 { OFCardGroupDivider() }
                    fixRow(for: result, itemID: itemID)
                }
            }

            if !hasSelectedFixItems {
                Text(OffsendStrings.directoryCheckFixSelectionNoneSelected)
                    .font(.system(size: 11))
                    .foregroundColor(.ofAmberText)
            } else if hasSelectedPatternsWithoutTargets {
                Text(OffsendStrings.directoryCheckFixSelectionNoPatternTargets)
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextMuted)
            }
        }
    }

    private func fixRowItemIDs(for result: AIWorkspacePrivacyAuditResult) -> [String] {
        fixItems(for: result).map(\.id)
    }

    private func fixRowContent(
        for result: AIWorkspacePrivacyAuditResult,
        item: AIWorkspacePrivacyFixItem,
        itemID: String
    ) -> (description: String, isPattern: Bool) {
        let isPattern: Bool
        if case .sensitivePattern = item.kind {
            isPattern = true
        } else {
            isPattern = false
        }

        let description: String
        if isPattern,
           let finding = result.missingSensitivePatterns.first(where: { $0.pattern.id == itemID }),
           !finding.exposedRelativePaths.isEmpty {
            description = sensitivePatternSubtitle(for: finding)
        } else if !isPattern,
                  let finding = result.ruleFindings.first(where: { $0.rule.id == itemID }),
                  !finding.exposedRelativePaths.isEmpty {
            description = ruleFindingSubtitle(for: finding)
        } else if isPattern, case let .sensitivePattern(canonicalLine) = item.kind {
            description = OffsendStrings.directoryCheckFixSelectionPatternAdd(canonicalLine)
        } else {
            description = fixItemSubtitle(for: item)
        }

        return (description, isPattern)
    }

    @ViewBuilder
    private func fixRow(for result: AIWorkspacePrivacyAuditResult, itemID: String) -> some View {
        let policyFilesEnabled = hasSelectedPolicyFiles(for: result)
        if let item = fixItems(for: result).first(where: { $0.id == itemID }) {
            let content = fixRowContent(for: result, item: item, itemID: itemID)

            OFSelectableFixRow(
                badgeStyle: severityTag(item.severity).badgeStyle,
                title: item.title,
                toolName: item.toolName,
                description: content.description,
                isSelected: selectedFixItemIDs.contains(itemID),
                isEnabled: content.isPattern ? policyFilesEnabled : true,
                isProLocked: isProOnlyFixItem(item)
            ) {
                toggleFixItemSelection(itemID, result: result)
            }
        }
    }

    private func findingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(.ofTextMuted)
                .padding(.horizontal, 2)

            OFCardGroup {
                content()
            }
        }
    }

    private func ruleFindingSubtitle(for finding: AIWorkspacePrivacyRuleFinding) -> String {
        guard !finding.exposedRelativePaths.isEmpty else {
            return finding.rule.remediation
        }
        return OffsendStrings.directoryCheckRuleExposedFiles(
            finding.rule.toolName,
            finding.exposedRelativePaths.joined(separator: ", ")
        )
    }

    private func sensitivePatternSubtitle(for finding: AIWorkspaceSensitivePatternFinding) -> String {
        guard !finding.exposedRelativePaths.isEmpty else {
            return finding.pattern.remediation
        }
        return OffsendStrings.directoryCheckExposedFiles(finding.exposedRelativePaths.joined(separator: ", "))
    }

    private func readOnlyFindingRow(
        title: String,
        subtitle: String,
        tag: FindingTag,
        toolName: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: OFSpacing.md) {
            OFStatusBadge(style: tag.badgeStyle, compact: true)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.ofText)

                    if let toolName {
                        Text(toolName)
                            .font(.system(size: 12))
                            .foregroundColor(.ofTextMuted)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, OFSpacing.md)
        .padding(.vertical, 12)
    }

    private func statusBadgeStyle(for status: AIWorkspacePrivacyAuditStatus) -> OFStatusBadgeStyle {
        switch status {
        case .pass:
            return .pass
        case .warning:
            return .warn
        case .fail:
            return .fail
        }
    }

    private var watchedEntryForSelection: WatchedDirectory? {
        guard let selectedDirectory else { return nil }
        return coordinator.watchedDirectoryEntry(matching: selectedDirectory)
    }

    private func cachedWatchStatusSection(for result: AIWorkspacePrivacyAuditResult) -> some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            HStack(alignment: .top, spacing: OFSpacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13))
                    .foregroundColor(.ofBlue)
                    .padding(.top, 1)

                Text(OffsendStrings.directoryCheckCachedWatchStatusHint)
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(OFSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ofBlueDim)
            .cornerRadius(OFRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.md)
                    .stroke(Color.ofBlue.opacity(0.25), lineWidth: 1)
            )

            HStack(spacing: OFSpacing.sm) {
                Text(OffsendStrings.directoryCheckCachedWatchStatusSummary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ofText)

                OFStatusCapsule(
                    style: statusBadgeStyle(for: result.status),
                    title: statusTitle(for: result.status)
                )

                Spacer(minLength: 0)

                OFButton(
                    title: OffsendStrings.directoryCheckRefreshAudit,
                    variant: .outline,
                    icon: "arrow.clockwise",
                    small: true
                ) {
                    audit(directoryURL: result.directoryURL)
                }
                .disabled(isBusy)
            }
        }
    }

    private func fixItemSubtitle(for item: AIWorkspacePrivacyFixItem) -> String {
        switch item.kind {
        case let .ruleFile(relativePath, strategy):
            switch strategy {
            case .createIfMissing:
                return OffsendStrings.directoryCheckFixSelectionRuleCreate(relativePath)
            case .mergeLines:
                return OffsendStrings.directoryCheckFixSelectionRuleUpdate(relativePath)
            }
        case let .sensitivePattern(canonicalLine):
            return OffsendStrings.directoryCheckFixSelectionPatternAdd(canonicalLine)
        }
    }

    private func toggleFixItemSelection(_ itemID: String, result: AIWorkspacePrivacyAuditResult) {
        let item = fixItems(for: result).first { $0.id == itemID }

        if selectedFixItemIDs.contains(itemID) {
            selectedFixItemIDs.remove(itemID)
            if case .ruleFile = item?.kind, !hasSelectedPolicyFiles(for: result) {
                clearPatternSelection(for: result)
            }
            return
        }

        if case .sensitivePattern = item?.kind, !hasSelectedPolicyFiles(for: result) {
            return
        }

        selectedFixItemIDs.insert(itemID)
    }

    private func auditChangesSection(_ delta: AIWorkspacePrivacyAuditDelta) -> some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Text(OffsendStrings.directoryCheckChangesTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.ofText)

            if delta.previousStatus != delta.currentStatus {
                Text(
                    OffsendStrings.directoryCheckChangesStatus(
                        statusTitle(for: delta.previousStatus),
                        statusTitle(for: delta.currentStatus)
                    )
                )
                .font(.system(size: 12))
                .foregroundColor(.ofTextSub)
            }

            ForEach(delta.newlyMissingRules, id: \.rule.id) { finding in
                Text(OffsendStrings.directoryCheckChangesNewlyMissingRule(finding.rule.title))
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.newlySatisfiedRules, id: \.rule.id) { finding in
                Text(OffsendStrings.directoryCheckChangesNewlySatisfiedRule(finding.rule.title))
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.newlyMissingPatterns, id: \.pattern.id) { finding in
                Text(OffsendStrings.directoryCheckChangesNewlyMissingPattern(finding.pattern.title))
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.newlySatisfiedPatterns, id: \.pattern.id) { finding in
                Text(OffsendStrings.directoryCheckChangesNewlySatisfiedPattern(finding.pattern.title))
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.removedMatchedPaths, id: \.self) { path in
                Text(OffsendStrings.directoryCheckChangesRemovedPath(path))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.addedMatchedPaths, id: \.self) { path in
                Text(OffsendStrings.directoryCheckChangesAddedPath(path))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.addedExposedRelativePaths, id: \.self) { path in
                Text(OffsendStrings.directoryCheckChangesAddedExposedPath(path))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.removedExposedRelativePaths, id: \.self) { path in
                Text(OffsendStrings.directoryCheckChangesRemovedExposedPath(path))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ofTextSub)
            }
        }
        .padding(OFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBorder, lineWidth: 1)
        )
    }

    private var proUpsellCard: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Label(OffsendStrings.directoryCheckProUpsellTitle, systemImage: "crown.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.ofBlue)

            Text(OffsendStrings.directoryCheckProUpsellBody)
                .font(.system(size: 12))
                .foregroundColor(.ofTextSub)
                .fixedSize(horizontal: false, vertical: true)

            OFButton(title: OffsendStrings.directoryCheckProUpsellCta, variant: .outline, icon: "arrow.up.right", small: true) {
                Task { await coordinator.openProCheckout(prefillEmail: nil) }
            }
        }
        .padding(OFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBorder, lineWidth: 1)
        )
    }


    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = OffsendStrings.directoryCheckChooseFolder

        if panel.runModal() == .OK, let url = panel.url {
            if effectiveSelectedDirectory != nil {
                coordinator.openDirectoryCheck(for: url, source: "directory_check_choose_another")
            } else {
                selectDirectory(url, runAudit: true)
            }
        }
    }

    private func bootstrapFromWindowPathIfNeeded() {
        guard let directoryWindowPath,
              let url = directoryURL(fromWindowPath: directoryWindowPath) else {
            return
        }
        let standardizedURL = url.standardizedFileURL
        guard selectedDirectory?.standardizedFileURL != standardizedURL else { return }
        selectDirectory(standardizedURL, runAudit: true)
    }

    private func directoryURL(fromWindowPath path: String) -> URL? {
        let url = URL(fileURLWithPath: path)
        guard isDirectory(url) else { return nil }
        return url
    }

    private func prefillDirectoryFromPasteboard() {
        guard selectedDirectory == nil, let directoryURL = directoryURLFromPasteboard() else {
            return
        }
        selectDirectory(directoryURL, runAudit: !coordinator.isDirectoryWatched(directoryURL))
    }

    private func selectDirectory(_ directoryURL: URL, runAudit: Bool) {
        let standardizedURL = directoryURL.standardizedFileURL
        selectedDirectory = standardizedURL
        isShowingCachedWatchStatus = false
        auditDelta = nil

        if runAudit {
            audit(directoryURL: standardizedURL)
            return
        }

        guard let entry = coordinator.watchedDirectoryEntry(matching: standardizedURL),
              let raw = entry.lastStatus,
              let status = AIWorkspacePrivacyAuditStatus(rawValue: raw) else {
            audit(directoryURL: standardizedURL)
            return
        }

        auditResult = placeholderAuditResult(for: standardizedURL, status: status)
        isShowingCachedWatchStatus = true
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let url = fileURL(from: item), isDirectory(url) else {
                return
            }

            DispatchQueue.main.async {
                if self.effectiveSelectedDirectory != nil {
                    self.coordinator.openDirectoryCheck(for: url, source: "directory_check_drop")
                } else {
                    self.selectDirectory(url, runAudit: true)
                }
            }
        }
        return true
    }

    private func audit(directoryURL: URL) {
        let standardizedURL = directoryURL.standardizedFileURL
        let configuration = auditConfiguration
        let token = UUID()

        selectedDirectory = standardizedURL
        fixMessage = nil
        auditToken = token
        isApplyingFix = false
        isAuditing = true
        isShowingCachedWatchStatus = false
        auditDelta = nil
        activeWork?.cancel()

        activeWork = Task {
            let result = await runAudit(directoryURL: standardizedURL, configuration: configuration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard auditToken == token else { return }
                isAuditing = false
                auditResult = result
                selectedFixItemIDs = defaultFixItemSelection(for: result)
                if let entry = coordinator.watchedDirectoryEntry(matching: standardizedURL) {
                    auditDelta = coordinator.computeWatchAuditDelta(watchID: entry.id, newResult: result)
                } else {
                    auditDelta = nil
                }
                coordinator.updateWatchedDirectorySnapshot(for: standardizedURL, result: result)
            }
        }
    }

    private func placeholderAuditResult(
        for directoryURL: URL,
        status: AIWorkspacePrivacyAuditStatus
    ) -> AIWorkspacePrivacyAuditResult {
        AIWorkspacePrivacyAuditResult(
            directoryURL: directoryURL,
            status: status,
            ruleFindings: [],
            sensitivePatternFindings: [],
            errors: []
        )
    }

    private func fix(_ result: AIWorkspacePrivacyAuditResult) {
        guard !isBusy else { return }
        guard !selectionRequiresPro(for: result) else { return }
        guard canApplyFixSelection(for: result) else { return }
        let selectionBeforeFix = selectedFixItemIDs
        let selection = fixSelection(for: result)
        guard !coordinator.settings.directoryCheckConfirmFix || confirmFix(for: result, selection: selection) else { return }

        let configuration = auditConfiguration
        let token = auditToken
        isApplyingFix = true
        activeWork?.cancel()

        activeWork = Task {
            let fixResult = await runFix(
                result: result,
                configuration: configuration,
                selection: selection
            )
            guard !Task.isCancelled else { return }
            let refreshedResult = await runAudit(
                directoryURL: result.directoryURL,
                configuration: configuration
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard auditToken == token else { return }
                isApplyingFix = false
                fixMessage = fixResultMessage(fixResult)
                auditResult = refreshedResult
                reconcileSelectionAfterFix(previousSelection: selectionBeforeFix, for: refreshedResult)
                let standardizedURL = result.directoryURL.standardizedFileURL
                if let entry = coordinator.watchedDirectoryEntry(matching: standardizedURL) {
                    auditDelta = coordinator.computeWatchAuditDelta(watchID: entry.id, newResult: refreshedResult)
                } else {
                    auditDelta = nil
                }
                coordinator.updateWatchedDirectorySnapshot(for: standardizedURL, result: refreshedResult)
            }
        }
    }

    private func runAudit(
        directoryURL: URL,
        configuration: AIWorkspacePrivacyAuditConfiguration
    ) async -> AIWorkspacePrivacyAuditResult {
        await Task.detached {
            AIWorkspacePrivacyAuditor().audit(directoryURL: directoryURL, configuration: configuration)
        }.value
    }

    private func runFix(
        result: AIWorkspacePrivacyAuditResult,
        configuration: AIWorkspacePrivacyAuditConfiguration,
        selection: AIWorkspacePrivacyFixSelection
    ) async -> AIWorkspacePrivacyFixResult {
        await Task.detached {
            AIWorkspacePrivacyFixer().fix(result: result, configuration: configuration, selection: selection)
        }.value
    }

    private func reconcileSelectionAfterFix(previousSelection: Set<String>, for result: AIWorkspacePrivacyAuditResult) {
        let availableIDs = Set(fixItems(for: result).map(\.id))
        selectedFixItemIDs = previousSelection.intersection(availableIDs)
    }

    private func confirmFix(for result: AIWorkspacePrivacyAuditResult, selection: AIWorkspacePrivacyFixSelection) -> Bool {
        let plannedPaths = plannedFixPaths(for: result, selection: selection)
        let alert = NSAlert()
        alert.messageText = OffsendStrings.directoryCheckConfirmTitle
        alert.informativeText = OffsendStrings.directoryCheckConfirmBody(
            result.directoryURL.lastPathComponent,
            plannedPaths.isEmpty ? "—" : plannedPaths.joined(separator: "\n")
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: OffsendStrings.directoryCheckConfirmApply)
        alert.addButton(withTitle: OffsendStrings.directoryCheckConfirmCancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func plannedFixPaths(
        for result: AIWorkspacePrivacyAuditResult,
        selection: AIWorkspacePrivacyFixSelection
    ) -> [String] {
        AIWorkspacePrivacyFixPlanner.plannedRelativePaths(
            for: result,
            configuration: auditConfiguration,
            selection: selection
        )
    }

    private func canFix(_ result: AIWorkspacePrivacyAuditResult) -> Bool {
        result.errors.isEmpty && result.status != .pass
    }

    private func fixResultMessage(_ result: AIWorkspacePrivacyFixResult) -> String {
        var parts: [String] = []
        if result.didChangeFiles {
            parts.append(fixSummary(result))
        } else if result.errors.isEmpty {
            return OffsendStrings.directoryCheckFixNoChanges
        }
        if !result.errors.isEmpty {
            parts.append(
                OffsendStrings.directoryCheckFixErrors(
                    result.errors.map(\.message).joined(separator: "\n")
                )
            )
        }
        return parts.joined(separator: "\n\n")
    }

    private func fixSummary(_ result: AIWorkspacePrivacyFixResult) -> String {
        if !result.didChangeFiles {
            return OffsendStrings.directoryCheckFixNoChanges
        }

        var parts: [String] = []
        if !result.createdRelativePaths.isEmpty {
            parts.append(OffsendStrings.directoryCheckFixCreated(result.createdRelativePaths.joined(separator: ", ")))
        }
        if !result.updatedRelativePaths.isEmpty {
            parts.append(OffsendStrings.directoryCheckFixUpdated(result.updatedRelativePaths.joined(separator: ", ")))
        }
        return parts.joined(separator: "\n")
    }

    private func directoryURLFromPasteboard() -> URL? {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL],
           let directoryURL = urls.map({ $0 as URL }).first(where: { isDirectory($0) }) {
            return directoryURL
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURLString),
           url.isFileURL,
           isDirectory(url) {
            return url
        }

        if let path = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if isDirectory(url) {
                return url
            }
        }

        return nil
    }

    nonisolated private func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }

    nonisolated private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func statusTitle(for status: AIWorkspacePrivacyAuditStatus) -> String {
        switch status {
        case .pass:
            return OffsendStrings.directoryCheckStatusPass
        case .warning:
            return OffsendStrings.directoryCheckStatusWarning
        case .fail:
            return OffsendStrings.directoryCheckStatusFail
        }
    }

    private func severityTag(_ severity: AIWorkspacePrivacyRuleSeverity) -> FindingTag {
        switch severity {
        case .required:
            return .fail
        case .recommended:
            return .warn
        case .informational:
            return .info
        }
    }
}

private struct DirectoryCheckAuditSettings: Equatable {
    let disabledRuleIDs: Set<String>
    let extraSkippedDirectories: [String]
    let customIgnoreTemplate: String?
}

private enum FindingTag {
    case pass
    case fail
    case warn
    case info

    var badgeStyle: OFStatusBadgeStyle {
        switch self {
        case .pass:
            return .pass
        case .fail:
            return .fail
        case .warn:
            return .warn
        case .info:
            return .info
        }
    }
}

private struct DirectoryCheckWindowSizer: NSViewRepresentable {
    let size: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            resizeWindow(for: view, animated: false)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            resizeWindow(for: nsView, animated: false)
        }
    }

    private func resizeWindow(for view: NSView, animated: Bool) {
        guard let window = view.window else { return }

        let current = window.contentRect(forFrameRect: window.frame).size
        guard abs(current.width - size.width) > 1 || abs(current.height - size.height) > 1 else {
            return
        }

        window.setContentSize(size, animated: animated)
    }
}

private extension NSWindow {
    func setContentSize(_ size: NSSize, animated: Bool) {
        guard animated else {
            setContentSize(size)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            setContentSize(size)
        }
    }
}
