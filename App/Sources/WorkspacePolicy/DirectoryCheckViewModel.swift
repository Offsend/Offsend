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

    func preferredWindowHeight() -> CGFloat {
        guard auditResult != nil else {
            return DirectoryCheckLayout.emptyStateHeight
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

    func fixScenario(for result: AIWorkspacePrivacyAuditResult) -> AIWorkspacePrivacyFixScenario {
        AIWorkspacePrivacyFixPlanner.fixScenario(for: result)
    }

    func ruleFileFixItems(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> [AIWorkspacePrivacyFixItem] {
        fixItems(for: result, coordinator: coordinator).filter {
            if case .ruleFile = $0.kind { return true }
            return false
        }
    }

    func exposureGapRuleFileItems(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> [AIWorkspacePrivacyFixItem] {
        AIWorkspacePrivacyFixPlanner.exposureGapRuleItems(
            from: ruleFileFixItems(for: result, coordinator: coordinator),
            result: result
        )
    }

    func missingRuleFileItems(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> [AIWorkspacePrivacyFixItem] {
        AIWorkspacePrivacyFixPlanner.missingRuleItems(
            from: ruleFileFixItems(for: result, coordinator: coordinator),
            result: result
        )
    }

    func missingIgnoreFileItems(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> [AIWorkspacePrivacyFixItem] {
        AIWorkspacePrivacyFixPlanner.missingIgnoreFileItems(
            for: result,
            configuration: coordinator.directoryCheckAuditConfiguration()
        )
    }

    /// Missing or updatable project rule files (.cursor/rules, …) — not AI ignore lists.
    func projectRuleFileFixItems(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> [AIWorkspacePrivacyFixItem] {
        ruleFileFixItems(for: result, coordinator: coordinator).filter { item in
            guard let finding = result.ruleFindings.first(where: { $0.rule.id == item.id }) else {
                return false
            }
            return !finding.rule.scansForSensitivePatterns
        }
    }

    /// Required or recommended rule findings that are not represented in the fix picker.
    func uncoveredRuleFindings(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> [AIWorkspacePrivacyRuleFinding] {
        let representedRuleIDs = Set(ruleFileFixItems(for: result, coordinator: coordinator).map(\.id))
            .union(Set(missingIgnoreFileItems(for: result, coordinator: coordinator).map(\.id)))
        return (result.missingRequiredRules + result.missingRecommendedRules)
            .filter { !representedRuleIDs.contains($0.rule.id) }
    }

    /// Missing project guidance files that are not AI ignore lists (.cursor/rules, AGENTS.md, …).
    func otherProjectFileFindings(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> [AIWorkspacePrivacyRuleFinding] {
        uncoveredRuleFindings(for: result, coordinator: coordinator)
            .filter { !$0.rule.scansForSensitivePatterns }
    }

    func showsPatternSelection(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> Bool {
        fixScenario(for: result) == .existingPolicyFiles
            && !patternFixItems(for: result, coordinator: coordinator).isEmpty
    }

    func patternFixItems(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> [AIWorkspacePrivacyFixItem] {
        fixItems(for: result, coordinator: coordinator).filter {
            if case .sensitivePattern = $0.kind { return true }
            return false
        }
    }

    func selectedRuleFileCount(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> Int {
        fixSelection(for: result, coordinator: coordinator).ruleIDs.count
    }

    func allRuleFilesSelected(items: [AIWorkspacePrivacyFixItem]) -> Bool {
        let itemIDs = Set(items.map(\.id))
        return !itemIDs.isEmpty && itemIDs.isSubset(of: selectedFixItemIDs)
    }

    func toggleSelectAllRuleFiles(
        items: [AIWorkspacePrivacyFixItem],
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) {
        let itemIDs = Set(items.map(\.id))
        if allRuleFilesSelected(items: items) {
            selectedFixItemIDs.subtract(itemIDs)
        } else {
            selectedFixItemIDs.formUnion(itemIDs)
        }
        syncImplicitPatternSelection(for: result, coordinator: coordinator)
    }

    var hasSelectedFixItems: Bool {
        !selectedFixItemIDs.isEmpty
    }

    func isUpdatingExistingIgnoreFile(
        _ item: AIWorkspacePrivacyFixItem,
        result: AIWorkspacePrivacyAuditResult
    ) -> Bool {
        guard case .ruleFile = item.kind else { return false }
        return AIWorkspacePrivacyFixPlanner.isExposureGapRuleItem(item, in: result)
    }

    func fixApplySummary(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> DirectoryCheckFixApplySummary {
        let selection = fixSelection(for: result, coordinator: coordinator)
        let items = fixItems(for: result, coordinator: coordinator)
        let selectedRuleItems = items.filter { item in
            guard selection.ruleIDs.contains(item.id) else { return false }
            if case .ruleFile = item.kind { return true }
            return false
        }

        let fileCount = selectedRuleItems.count
        let patternFixCount: Int
        if selection.ruleIDs.isEmpty {
            patternFixCount = 0
        } else if usesImplicitPatternSelection(for: result, coordinator: coordinator) {
            patternFixCount = result.missingSensitivePatterns.count
        } else {
            patternFixCount = selection.patternIDs.count
        }

        let createsNewFilesOnly = !selectedRuleItems.isEmpty && selectedRuleItems.allSatisfy { item in
            guard case .ruleFile(_, let strategy) = item.kind else { return false }
            return strategy == .createIfMissing
        }
        let updatesExistingFiles = selectedRuleItems.contains {
            isUpdatingExistingIgnoreFile($0, result: result)
        }

        return DirectoryCheckFixApplySummary(
            patternFixCount: patternFixCount,
            fileCount: fileCount,
            createsNewFilesOnly: createsNewFilesOnly,
            updatesExistingFiles: updatesExistingFiles
        )
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

    func toggleFixItemSelection(
        _ itemID: String,
        result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) {
        let item = fixItems(for: result, coordinator: coordinator).first { $0.id == itemID }

        if case .sensitivePattern = item?.kind {
            guard hasSelectedPolicyFiles(for: result, coordinator: coordinator) else { return }
            if selectedFixItemIDs.contains(itemID) {
                selectedFixItemIDs.remove(itemID)
            } else {
                selectedFixItemIDs.insert(itemID)
            }
            return
        }

        guard case .ruleFile = item?.kind else { return }

        if selectedFixItemIDs.contains(itemID) {
            selectedFixItemIDs.remove(itemID)
            syncImplicitPatternSelection(for: result, coordinator: coordinator)
            return
        }

        selectedFixItemIDs.insert(itemID)
        syncImplicitPatternSelection(for: result, coordinator: coordinator)
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
        let selection = AIWorkspacePrivacyFixPlanner.defaultSelection(for: items, result: result)
        return selection.ruleIDs.union(selection.patternIDs)
    }

    func usesImplicitPatternSelection(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) -> Bool {
        !showsPatternSelection(for: result, coordinator: coordinator)
    }

    func syncImplicitPatternSelection(
        for result: AIWorkspacePrivacyAuditResult,
        coordinator: AppCoordinator
    ) {
        let patternIDs = Set(patternFixItems(for: result, coordinator: coordinator).map(\.id))
        guard !patternIDs.isEmpty else { return }

        if hasSelectedPolicyFiles(for: result, coordinator: coordinator) {
            selectedFixItemIDs.formUnion(patternIDs)
        } else {
            selectedFixItemIDs.subtract(patternIDs)
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
        syncImplicitPatternSelection(for: result, coordinator: coordinator)
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
