import AppKit
import AppUIKit
import Foundation
import SwiftUI
import StorageCore
import WorkspacePolicyCore

@MainActor
final class DirectoryCheckViewModel: ObservableObject {
    @Published private(set) var selectedDirectory: URL
    @Published private(set) var auditResult: AIWorkspacePrivacyAuditResult?
    @Published private(set) var fixMessage: String?
    @Published var selectedFixItemIDs: Set<String> = []
    @Published private(set) var isAuditing = false
    @Published private(set) var isApplyingFix = false
    @Published private(set) var isShowingCachedWatchStatus = false
    @Published private(set) var auditDelta: AIWorkspacePrivacyAuditDelta?
    @Published var windowResetToken = UUID()

    private weak var coordinator: AppCoordinator?
    private var auditToken = UUID()
    private var activeWork: Task<Void, Never>?

    var isBusy: Bool { isAuditing || isApplyingFix }

    init(directoryURL: URL) {
        selectedDirectory = directoryURL.standardizedFileURL
    }

    func bind(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func handleAppear() {
        windowResetToken = UUID()
        guard let coordinator else { return }
        if auditResult == nil, !isAuditing {
            selectDirectory(selectedDirectory, runAudit: !coordinator.isDirectoryWatched(selectedDirectory))
        }
    }

    func releaseSession() {
        activeWork?.cancel()
        activeWork = nil
    }

    func preferredWindowHeight(showsFreeBanner: Bool) -> CGFloat {
        guard auditResult != nil else {
            var height = DirectoryCheckLayout.emptyStateHeight
            if showsFreeBanner {
                height += DirectoryCheckLayout.freeBannerExtra
            }
            return height
        }
        return DirectoryCheckLayout.resultStateHeight
    }

    func auditSettings(from coordinator: AppCoordinator) -> DirectoryCheckAuditSettings {
        DirectoryCheckAuditSettings(
            disabledRuleIDs: coordinator.settings.directoryCheckDisabledRuleIDs,
            extraSkippedDirectories: coordinator.settings.directoryCheckExtraSkippedDirectories,
            customIgnoreTemplate: coordinator.settings.directoryCheckCustomIgnoreTemplate
        )
    }

    func canAutofix(coordinator: AppCoordinator) -> Bool {
        coordinator.licenseState.plan == .pro && coordinator.tariffFeatures.workspaceAuditAutofix
    }

    func shouldShowPinnedFooter(for result: AIWorkspacePrivacyAuditResult, coordinator: AppCoordinator) -> Bool {
        canFix(result) && !fixItems(for: result, coordinator: coordinator).isEmpty
    }

    func showsProtectedState(_ result: AIWorkspacePrivacyAuditResult) -> Bool {
        result.status == .pass
            && result.errors.isEmpty
            && result.missingRequiredRules.isEmpty
            && result.missingSensitivePatterns.isEmpty
            && result.missingRecommendedRules.isEmpty
    }

    func totalPrivacyRules(for result: AIWorkspacePrivacyAuditResult) -> Int {
        result.ruleFindings.count + result.sensitivePatternFindings.count
    }

    func isWatchingSelectedDirectory(coordinator: AppCoordinator) -> Bool {
        guard let entry = watchedEntryForSelection(coordinator: coordinator) else {
            return false
        }
        return coordinator.settings.directoryWatchEnabled
            && !coordinator.isDirectoryWatchPaused(entry)
    }

    func watchSubtitle(coordinator: AppCoordinator) -> String {
        if isWatchingSelectedDirectory(coordinator: coordinator) {
            return OffsendStrings.directoryCheckWatchOnHint
        }
        if isWatchPausedForSelection(coordinator: coordinator) {
            return OffsendStrings.settingsDirectoryCheckMonitoredPaused
        }
        if isWatchBlockedByFreePlan(coordinator: coordinator) {
            return OffsendStrings.settingsDirectoryCheckMonitoredLimitReached
        }
        return OffsendStrings.directoryCheckWatchOffHint
    }

    func watchSubtitleTint(coordinator: AppCoordinator) -> Color {
        if isWatchingSelectedDirectory(coordinator: coordinator) {
            return .ofGreenText
        }
        if showsWatchFreePlanUpgrade(coordinator: coordinator) {
            return .ofAmberText
        }
        return .ofTextSub
    }

    func showsWatchFreePlanUpgrade(coordinator: AppCoordinator) -> Bool {
        isWatchBlockedByFreePlan(coordinator: coordinator)
            || isWatchPausedForSelection(coordinator: coordinator)
    }

    func isWatchToggleEnabled(coordinator: AppCoordinator) -> Bool {
        isWatchingSelectedDirectory(coordinator: coordinator)
            || !isWatchBlockedByFreePlan(coordinator: coordinator)
    }

    func isWatchPausedForSelection(coordinator: AppCoordinator) -> Bool {
        guard let entry = watchedEntryForSelection(coordinator: coordinator) else {
            return false
        }
        return coordinator.isDirectoryWatchPaused(entry)
    }

    func isWatchBlockedByFreePlan(coordinator: AppCoordinator) -> Bool {
        guard !coordinator.tariffFeatures.workspaceAuditFull else { return false }
        guard !isWatchingSelectedDirectory(coordinator: coordinator) else { return false }
        guard !isWatchPausedForSelection(coordinator: coordinator) else { return false }

        return !coordinator.canAddMoreWatchedDirectories
            && !coordinator.isDirectoryWatched(selectedDirectory)
    }

    func toggleWatchForSelectedDirectory(enabled: Bool, coordinator: AppCoordinator) {
        if enabled {
            if coordinator.addWatchedDirectory(url: selectedDirectory, source: "directory_check") {
                return
            }
            Task { await coordinator.upgradeFromWatchLimit(source: "directory_check") }
        } else if let entry = watchedEntryForSelection(coordinator: coordinator) {
            coordinator.removeWatchedDirectory(id: entry.id)
        }
    }

    func fixItems(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> [AIWorkspacePrivacyFixItem] {
        AIWorkspacePrivacyFixPlanner.fixItems(
            for: result,
            configuration: coordinator.directoryCheckAuditConfiguration()
        )
    }

    func allFixItemsSelected(for result: AIWorkspacePrivacyAuditResult, coordinator: AppCoordinator) -> Bool {
        let itemIDs = Set(fixItems(for: result, coordinator: coordinator).map(\.id))
        return !itemIDs.isEmpty && itemIDs.isSubset(of: selectedFixItemIDs)
    }

    var hasSelectedFixItems: Bool {
        !selectedFixItemIDs.isEmpty
    }

    func canApplyFixSelection(for result: AIWorkspacePrivacyAuditResult, coordinator: AppCoordinator) -> Bool {
        guard hasSelectedFixItems else { return false }
        let selection = fixSelection(for: result, coordinator: coordinator)
        if selection.ruleIDs.isEmpty && !selection.patternIDs.isEmpty {
            return false
        }
        if !selection.patternIDs.isEmpty {
            return !patternTargetPaths(for: result, selection: selection, coordinator: coordinator).isEmpty
        }
        return true
    }

    func hasSelectedPolicyFiles(for result: AIWorkspacePrivacyAuditResult, coordinator: AppCoordinator) -> Bool {
        !fixSelection(for: result, coordinator: coordinator).ruleIDs.isEmpty
    }

    func hasSelectedPatternsWithoutTargets(for result: AIWorkspacePrivacyAuditResult, coordinator: AppCoordinator) -> Bool {
        !hasSelectedPolicyFiles(for: result, coordinator: coordinator)
            && fixItems(for: result, coordinator: coordinator).contains {
                if case .sensitivePattern = $0.kind { return true }
                return false
            }
    }

    func isFreeApplicableFixItem(_ item: AIWorkspacePrivacyFixItem) -> Bool {
        switch item.kind {
        case .ruleFile:
            return AIWorkspacePrivacyAuditConfiguration.freeFixableRuleIDs.contains(item.id)
        case .sensitivePattern:
            return true
        }
    }

    func isProOnlyFixItem(_ item: AIWorkspacePrivacyFixItem, coordinator: AppCoordinator) -> Bool {
        guard !canAutofix(coordinator: coordinator) else { return false }
        return !isFreeApplicableFixItem(item)
    }

    func selectionRequiresPro(for result: AIWorkspacePrivacyAuditResult, coordinator: AppCoordinator) -> Bool {
        guard !canAutofix(coordinator: coordinator) else { return false }
        return fixItems(for: result, coordinator: coordinator).contains {
            selectedFixItemIDs.contains($0.id) && isProOnlyFixItem($0, coordinator: coordinator)
        }
    }

    func toggleFixItemSelection(
        _ itemID: String,
        result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) {
        let item = fixItems(for: result, coordinator: coordinator).first { $0.id == itemID }

        if selectedFixItemIDs.contains(itemID) {
            selectedFixItemIDs.remove(itemID)
            if case .ruleFile = item?.kind, !hasSelectedPolicyFiles(for: result, coordinator: coordinator) {
                clearPatternSelection(for: result, coordinator: coordinator)
            }
            return
        }

        if case .sensitivePattern = item?.kind, !hasSelectedPolicyFiles(for: result, coordinator: coordinator) {
            return
        }

        selectedFixItemIDs.insert(itemID)
    }

    func toggleSelectAllFixItems(for result: AIWorkspacePrivacyAuditResult, coordinator: AppCoordinator) {
        let items = fixItems(for: result, coordinator: coordinator)
        if allFixItemsSelected(for: result, coordinator: coordinator) {
            selectedFixItemIDs.removeAll()
        } else {
            selectedFixItemIDs = Set(items.map(\.id))
        }
    }

    func fixRowContent(
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
            description = DirectoryCheckPresentation.sensitivePatternSubtitle(for: finding)
        } else if !isPattern,
                  let finding = result.ruleFindings.first(where: { $0.rule.id == itemID }),
                  !finding.exposedRelativePaths.isEmpty {
            description = DirectoryCheckPresentation.ruleFindingSubtitle(for: finding)
        } else if isPattern, case let .sensitivePattern(canonicalLine) = item.kind {
            description = OffsendStrings.directoryCheckFixSelectionPatternAdd(canonicalLine)
        } else {
            description = DirectoryCheckPresentation.fixItemSubtitle(for: item)
        }

        return (description, isPattern)
    }

    func selectDirectory(_ directoryURL: URL, runAudit: Bool) {
        let standardizedURL = directoryURL.standardizedFileURL
        selectedDirectory = standardizedURL
        isShowingCachedWatchStatus = false
        auditDelta = nil

        if runAudit {
            audit(directoryURL: standardizedURL)
            return
        }

        guard let coordinator,
              let entry = coordinator.watchedDirectoryEntry(matching: standardizedURL),
              let raw = entry.lastStatus,
              let status = AIWorkspacePrivacyAuditStatus(rawValue: raw) else {
            audit(directoryURL: standardizedURL)
            return
        }

        auditResult = placeholderAuditResult(for: standardizedURL, status: status)
        isShowingCachedWatchStatus = true
    }

    func audit(directoryURL: URL) {
        guard let coordinator else { return }

        let standardizedURL = directoryURL.standardizedFileURL
        let configuration = coordinator.directoryCheckAuditConfiguration()
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
                selectedFixItemIDs = defaultFixItemSelection(for: result, coordinator: coordinator)
                if let entry = coordinator.watchedDirectoryEntry(matching: standardizedURL) {
                    auditDelta = coordinator.computeWatchAuditDelta(watchID: entry.id, newResult: result)
                } else {
                    auditDelta = nil
                }
                coordinator.updateWatchedDirectorySnapshot(for: standardizedURL, result: result)
            }
        }
    }

    func fix(_ result: AIWorkspacePrivacyAuditResult, coordinator: AppCoordinator) {
        guard !isBusy else { return }
        guard !selectionRequiresPro(for: result, coordinator: coordinator) else { return }
        guard canApplyFixSelection(for: result, coordinator: coordinator) else { return }

        let selectionBeforeFix = selectedFixItemIDs
        let selection = fixSelection(for: result, coordinator: coordinator)
        guard !coordinator.settings.directoryCheckConfirmFix || confirmFix(for: result, selection: selection, coordinator: coordinator) else {
            return
        }

        let configuration = coordinator.directoryCheckAuditConfiguration()
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
                fixMessage = DirectoryCheckPresentation.fixResultMessage(fixResult)
                auditResult = refreshedResult
                reconcileSelectionAfterFix(
                    previousSelection: selectionBeforeFix,
                    for: refreshedResult,
                    coordinator: coordinator
                )
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
}

// MARK: - Private helpers

private extension DirectoryCheckViewModel {
    func watchedEntryForSelection(coordinator: AppCoordinator) -> WatchedDirectory? {
        coordinator.watchedDirectoryEntry(matching: selectedDirectory)
    }

    func defaultFixItemSelection(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> Set<String> {
        let items = fixItems(for: result, coordinator: coordinator)
        let applicableItems = canAutofix(coordinator: coordinator)
            ? items
            : items.filter { isFreeApplicableFixItem($0) }
        let selection = AIWorkspacePrivacyFixPlanner.defaultSelection(for: applicableItems, result: result)
        return selection.ruleIDs.union(selection.patternIDs)
    }

    func clearPatternSelection(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) {
        for item in fixItems(for: result, coordinator: coordinator) {
            if case .sensitivePattern = item.kind {
                selectedFixItemIDs.remove(item.id)
            }
        }
    }

    func patternTargetPaths(
        for result: AIWorkspacePrivacyAuditResult,
        selection: AIWorkspacePrivacyFixSelection,
        coordinator: AppCoordinator
    ) -> [String] {
        AIWorkspacePrivacyFixPlanner.patternTargetRelativePaths(
            for: result,
            configuration: coordinator.directoryCheckAuditConfiguration(),
            selection: selection
        )
    }

    func fixSelection(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> AIWorkspacePrivacyFixSelection {
        AIWorkspacePrivacyFixPlanner.selection(
            from: selectedFixItemIDs,
            in: fixItems(for: result, coordinator: coordinator)
        )
    }

    func placeholderAuditResult(
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

    func runAudit(
        directoryURL: URL,
        configuration: AIWorkspacePrivacyAuditConfiguration
    ) async -> AIWorkspacePrivacyAuditResult {
        await Task.detached {
            AIWorkspacePrivacyAuditor().audit(directoryURL: directoryURL, configuration: configuration)
        }.value
    }

    func runFix(
        result: AIWorkspacePrivacyAuditResult,
        configuration: AIWorkspacePrivacyAuditConfiguration,
        selection: AIWorkspacePrivacyFixSelection
    ) async -> AIWorkspacePrivacyFixResult {
        await Task.detached {
            AIWorkspacePrivacyFixer().fix(result: result, configuration: configuration, selection: selection)
        }.value
    }

    func reconcileSelectionAfterFix(
        previousSelection: Set<String>,
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) {
        let availableIDs = Set(fixItems(for: result, coordinator: coordinator).map(\.id))
        selectedFixItemIDs = previousSelection.intersection(availableIDs)
    }

    func confirmFix(
        for result: AIWorkspacePrivacyAuditResult,
        selection: AIWorkspacePrivacyFixSelection,
        coordinator: AppCoordinator
    ) -> Bool {
        let plannedPaths = AIWorkspacePrivacyFixPlanner.plannedRelativePaths(
            for: result,
            configuration: coordinator.directoryCheckAuditConfiguration(),
            selection: selection
        )
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

    func canFix(_ result: AIWorkspacePrivacyAuditResult) -> Bool {
        result.errors.isEmpty && result.status != .pass
    }
}
