import Foundation
import StorageCore
import UserNotifications
import WorkspacePolicyCore
import WorkspaceWatchService

struct WorkspaceWatchRuntimeState: Equatable {
    var statusByWatchID: [UUID: AIWorkspacePrivacyAuditStatus] = [:]
    var lastResultByWatchID: [UUID: AIWorkspacePrivacyAuditResult] = [:]
    var isAuditing: Set<UUID> = []
    var unavailableWatchIDs: Set<UUID> = []
}

extension AppCoordinator {
    var directoryWatchLimit: Int? {
        DirectoryWatchLimits.maxRoots(workspaceAuditFull: tariffFeatures.workspaceAuditFull)
    }

    var canAddMoreWatchedDirectories: Bool {
        DirectoryWatchLimits.canAddMore(
            currentCount: settings.watchedDirectories.count,
            workspaceAuditFull: tariffFeatures.workspaceAuditFull
        )
    }

    func directoryCheckAuditConfiguration() -> AIWorkspacePrivacyAuditConfiguration {
        DirectoryCheckConfigurationResolver.resolve(
            DirectoryCheckConfigurationInput(
                disabledRuleIDs: settings.directoryCheckDisabledRuleIDs,
                extraSkippedDirectories: settings.directoryCheckExtraSkippedDirectories,
                customIgnoreTemplate: settings.directoryCheckCustomIgnoreTemplate
            )
        )
    }

    func isDirectoryWatched(_ url: URL) -> Bool {
        watchedDirectoryEntry(matching: url) != nil
    }

    func watchedDirectoryEntry(matching url: URL) -> WatchedDirectory? {
        guard let index = WatchedDirectoryPathMatcher.firstIndex(
            in: settings.watchedDirectories,
            matching: url
        ) else {
            return nil
        }
        return settings.watchedDirectories[index]
    }

    func isDirectoryWatchPaused(_ entry: WatchedDirectory) -> Bool {
        let activeIDs = Set(activeWatchedDirectoryEntries().map(\.id))
        return !activeIDs.contains(entry.id)
    }

    func applyDirectoryWatchChanges(previous: DirectoryWatchSettingsSnapshot) {
        let current = DirectoryWatchSettingsSnapshot(
            settings: settings,
            workspaceAuditFull: tariffFeatures.workspaceAuditFull
        )
        let actions = current.updateActions(comparedToPrevious: previous)

        if actions.reloadStreams {
            reloadDirectoryWatch(runInitialAudits: false)
        }

        if actions.reauditActiveDirectories {
            reauditActiveWatchedDirectories(force: true)
        }
    }

    @discardableResult
    func addWatchedDirectory(url: URL, source: String = "settings") -> Bool {
        guard canAddMoreWatchedDirectories else { return false }

        let standardized = url.standardizedFileURL
        if isDirectoryWatched(standardized) {
            return true
        }

        let accessed = standardized.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                standardized.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmark = try WatchedDirectoryBookmark.make(from: standardized)
            let entry = WatchedDirectory(
                displayName: standardized.lastPathComponent,
                bookmarkData: bookmark,
                resolvedPath: WatchedDirectoryPathMatcher.standardizedPath(for: standardized)
            )
            let wasWatchEnabled = settings.directoryWatchEnabled
            settings.watchedDirectories.append(entry)
            if !settings.directoryWatchEnabled {
                settings.directoryWatchEnabled = true
            }
            saveSettings()
            if !wasWatchEnabled {
                analytics.track(.watchEnabled)
            }
            analytics.track(.watchDirectoryAdded(source: source))
            runWatchAudit(watchID: entry.id, rootURL: standardized, force: true)
            return true
        } catch {
            lastStatusMessage = error.localizedDescription
            return false
        }
    }

    func setDirectoryWatchEnabled(_ enabled: Bool) {
        let wasEnabled = settings.directoryWatchEnabled
        settings.directoryWatchEnabled = enabled
        if enabled, !wasEnabled {
            analytics.track(.watchEnabled)
        }
        saveSettings()
    }

    func upgradeFromWatchLimit(source: String) async {
        analytics.track(.watchUpgradeFromLimit(source: source))
        await openProCheckout(prefillEmail: nil, source: "watch_limit_\(source)")
    }

    @discardableResult
    func replaceWatchedDirectoryBookmark(id: UUID, url: URL) -> Bool {
        guard let index = settings.watchedDirectories.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let standardized = url.standardizedFileURL
        if let duplicateIndex = WatchedDirectoryPathMatcher.firstIndex(
            in: settings.watchedDirectories,
            matching: standardized
        ), settings.watchedDirectories[duplicateIndex].id != id {
            return false
        }

        let accessed = standardized.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                standardized.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmark = try WatchedDirectoryBookmark.make(from: standardized)
            settings.watchedDirectories[index].bookmarkData = bookmark
            settings.watchedDirectories[index].resolvedPath = WatchedDirectoryPathMatcher.standardizedPath(for: standardized)
            settings.watchedDirectories[index].displayName = standardized.lastPathComponent
            directoryWatchRuntime.unavailableWatchIDs.remove(id)
            saveSettings()
            runWatchAudit(watchID: id, rootURL: standardized, force: true)
            return true
        } catch {
            lastStatusMessage = error.localizedDescription
            return false
        }
    }

    func removeWatchedDirectory(id: UUID) {
        cancelWatchAudit(watchID: id)
        settings.watchedDirectories.removeAll { $0.id == id }
        directoryWatchRuntime.statusByWatchID.removeValue(forKey: id)
        directoryWatchRuntime.lastResultByWatchID.removeValue(forKey: id)
        directoryWatchRuntime.unavailableWatchIDs.remove(id)
        analytics.track(.watchDirectoryRemoved)
        saveSettings()
    }

    func reloadDirectoryWatch(runInitialAudits: Bool = false) {
        applyDirectoryWatchPreference(runInitialAudits: runInitialAudits)
    }

    func updateWatchedDirectorySnapshot(for url: URL, result: AIWorkspacePrivacyAuditResult) {
        guard let index = WatchedDirectoryPathMatcher.firstIndex(
            in: settings.watchedDirectories,
            matching: url
        ) else {
            return
        }

        settings.watchedDirectories[index].lastAuditAt = Date()
        settings.watchedDirectories[index].lastStatus = result.status.rawValue
        settings.watchedDirectories[index].resolvedPath = WatchedDirectoryPathMatcher.standardizedPath(for: result.directoryURL)
        directoryWatchRuntime.statusByWatchID[settings.watchedDirectories[index].id] = result.status
        directoryWatchRuntime.lastResultByWatchID[settings.watchedDirectories[index].id] = result
        persistWatchSettings()
        refreshMenuBarStatusItem()
    }

    func bootstrapDirectoryWatch() {
        applyDirectoryWatchPreference(runInitialAudits: true)
    }

    func handleWorkspaceWatchNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        guard let watchIDString = userInfo["watchID"] as? String,
              let watchID = UUID(uuidString: watchIDString) else {
            return
        }

        analytics.track(.watchNotificationOpened(action: response.actionIdentifier))

        let isUnavailable = userInfo["directoryUnavailable"] as? String == "1"

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier, "open", "openSettings":
            if isUnavailable {
                openDirectoryCheckSettings(source: "notification")
            } else {
                openDirectoryCheckForWatch(watchID: watchID, source: "notification")
            }
        case "fix":
            if isUnavailable {
                openDirectoryCheckSettings(source: "notification")
            } else {
                applyWorkspaceWatchFixFromNotification(watchID: watchID)
            }
        default:
            break
        }
    }

    func openDirectoryCheckSettings(source: String) {
        pendingSettingsTab = .directoryCheck
        openSettingsWindowAction?()
        recordDirectoryCheckOpened(source: source)
    }

    func openDirectoryCheckForWatch(watchID: UUID, source: String) {
        if directoryWatchRuntime.unavailableWatchIDs.contains(watchID) {
            openDirectoryCheckSettings(source: source)
            return
        }

        let url = settings.watchedDirectories
            .first(where: { $0.id == watchID })
            .flatMap(\.resolvedPath)
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
        guard let url else {
            openDirectoryCheckSettings(source: source)
            return
        }
        openPrepare(for: url, source: source)
    }

    func openDirectoryCheck(for url: URL, source: String) {
        openPrepare(for: url, source: source)
    }

    func recordDirectoryCheckOpened(source: String) {
        analytics.track(.directoryCheckOpened(source: source))
    }

    func computeWatchAuditDelta(
        watchID: UUID,
        newResult: AIWorkspacePrivacyAuditResult
    ) -> AIWorkspacePrivacyAuditDelta? {
        guard let previous = directoryWatchRuntime.lastResultByWatchID[watchID] else {
            return nil
        }
        let delta = AIWorkspacePrivacyAuditDelta.compute(from: previous, to: newResult)
        return delta.hasChanges ? delta : nil
    }

    func applyDirectoryWatchPreference(runInitialAudits: Bool = false) {
        defer { markDirectoryWatchSnapshotApplied() }

        guard settings.directoryWatchEnabled, !settings.watchedDirectories.isEmpty else {
            cancelAllWatchAudits()
            workspaceWatchService.stopWatching()
            if !settings.directoryWatchEnabled {
                directoryWatchRuntime = WorkspaceWatchRuntimeState()
            }
            refreshMenuBarStatusItem()
            return
        }

        requestNotificationAuthorizationIfNeeded()

        var resolvedRoots: [(id: UUID, url: URL)] = []
        var unavailable: Set<UUID> = []
        let activeEntries = activeWatchedDirectoryEntries()
        let activeIDs = Set(activeEntries.map(\.id))

        for index in settings.watchedDirectories.indices {
            let entry = settings.watchedDirectories[index]
            guard activeIDs.contains(entry.id) else { continue }

            do {
                let resolution = try WatchedDirectoryBookmark.resolve(entry.bookmarkData)
                let url = resolution.url
                settings.watchedDirectories[index].resolvedPath = WatchedDirectoryPathMatcher.standardizedPath(for: url)

                if resolution.bookmarkWasStale,
                   let refreshed = try? WatchedDirectoryBookmark.refreshBookmark(for: url) {
                    settings.watchedDirectories[index].bookmarkData = refreshed
                }

                guard WorkspaceDirectoryAvailability.isReadableDirectory(at: url) else {
                    unavailable.insert(entry.id)
                    continue
                }

                resolvedRoots.append((entry.id, url))
                if directoryWatchRuntime.statusByWatchID[entry.id] == nil,
                   let raw = entry.lastStatus,
                   let status = AIWorkspacePrivacyAuditStatus(rawValue: raw) {
                    directoryWatchRuntime.statusByWatchID[entry.id] = status
                }
            } catch {
                unavailable.insert(entry.id)
            }
        }

        directoryWatchRuntime.unavailableWatchIDs = unavailable
        persistWatchSettings()

        workspaceWatchService.startWatching(
            roots: resolvedRoots,
            configuration: directoryCheckAuditConfiguration()
        ) { [weak self] watchID, rootURL, changedPaths in
            Task { @MainActor [weak self] in
                self?.runWatchAudit(
                    watchID: watchID,
                    rootURL: rootURL,
                    force: false,
                    changedRelativePaths: changedPaths
                )
            }
        }

        if runInitialAudits {
            for (id, url) in resolvedRoots {
                runWatchAudit(watchID: id, rootURL: url, force: true)
            }
        }

        refreshMenuBarStatusItem()
    }

    func reauditActiveWatchedDirectories(force: Bool) {
        guard settings.directoryWatchEnabled else { return }
        for entry in activeWatchedDirectoryEntries() {
            guard let path = entry.resolvedPath else { continue }
            runWatchAudit(
                watchID: entry.id,
                rootURL: URL(fileURLWithPath: path),
                force: force
            )
        }
    }

    func runWatchAudit(
        watchID: UUID,
        rootURL: URL,
        force: Bool,
        changedRelativePaths: Set<String>? = nil
    ) {
        guard settings.directoryWatchEnabled else { return }
        guard activeWatchedDirectoryEntries().contains(where: { $0.id == watchID }) else { return }

        if directoryWatchRuntime.isAuditing.contains(watchID) {
            if watchAuditTasks[watchID] != nil {
                queuePendingWatchAudit(watchID: watchID, changedRelativePaths: changedRelativePaths)
                return
            }
            directoryWatchRuntime.isAuditing.remove(watchID)
        }

        let lastAuditAt = settings.watchedDirectories.first(where: { $0.id == watchID })?.lastAuditAt
        let configuration = directoryCheckAuditConfiguration()
        let hasSensitivePathChange = changedRelativePaths.map { paths in
            paths.contains { path in
                path.isEmpty
                    || SensitivePathMatcher.matchingPattern(
                        relativePath: path,
                        patterns: configuration.sensitivePatterns
                    ) != nil
            }
        } ?? false
        guard DirectoryWatchAuditThrottle.shouldRunAudit(
            lastAuditAt: lastAuditAt,
            force: force || hasSensitivePathChange
        ) else {
            queuePendingWatchAudit(watchID: watchID, changedRelativePaths: changedRelativePaths)
            scheduleThrottledWatchAuditRetry(watchID: watchID, rootURL: rootURL, lastAuditAt: lastAuditAt)
            return
        }

        watchAuditRetryTasks[watchID]?.cancel()
        watchAuditRetryTasks.removeValue(forKey: watchID)

        directoryWatchRuntime.isAuditing.insert(watchID)
        let auditStartedAt = Date()
        let previousStatus = directoryWatchRuntime.statusByWatchID[watchID]
            ?? settings.watchedDirectories.first(where: { $0.id == watchID })?.lastStatus
            .flatMap(AIWorkspacePrivacyAuditStatus.init(rawValue:))
        let previousResultAtStart = directoryWatchRuntime.lastResultByWatchID[watchID]

        watchAuditTasks[watchID] = Task { @MainActor in
            defer {
                directoryWatchRuntime.isAuditing.remove(watchID)
                watchAuditTasks.removeValue(forKey: watchID)
                schedulePendingWatchAuditIfNeeded(watchID: watchID, rootURL: rootURL)
            }

            let result = await Task.detached(priority: .utility) {
                let auditor = AIWorkspacePrivacyAuditor()
                if let changedRelativePaths,
                   !changedRelativePaths.isEmpty,
                   !hasSensitivePathChange,
                   let previousResultAtStart,
                   let deltaResult = auditor.auditDelta(
                    directoryURL: rootURL,
                    changedRelativePaths: changedRelativePaths,
                    previousResult: previousResultAtStart,
                    configuration: configuration
                   ) {
                    return deltaResult
                }
                return auditor.audit(directoryURL: rootURL, configuration: configuration)
            }.value

            guard !Task.isCancelled else { return }
            guard activeWatchedDirectoryEntries().contains(where: { $0.id == watchID }) else { return }

            handleWatchAuditResult(
                watchID: watchID,
                result: result,
                previousStatus: previousStatus,
                previousResultAtStart: previousResultAtStart,
                auditStartedAt: auditStartedAt
            )
        }
    }

    private func queuePendingWatchAudit(watchID: UUID, changedRelativePaths: Set<String>?) {
        if let changedRelativePaths, !changedRelativePaths.isEmpty {
            pendingWatchAuditChanges[watchID, default: []].formUnion(changedRelativePaths)
        } else {
            pendingWatchAuditNeedsFull.insert(watchID)
        }
    }

    private func schedulePendingWatchAuditIfNeeded(watchID: UUID, rootURL: URL) {
        if pendingWatchAuditNeedsFull.contains(watchID) {
            pendingWatchAuditNeedsFull.remove(watchID)
            pendingWatchAuditChanges.removeValue(forKey: watchID)
            runWatchAudit(watchID: watchID, rootURL: rootURL, force: true)
            return
        }

        guard let pendingPaths = pendingWatchAuditChanges.removeValue(forKey: watchID), !pendingPaths.isEmpty else {
            return
        }

        runWatchAudit(
            watchID: watchID,
            rootURL: rootURL,
            force: false,
            changedRelativePaths: pendingPaths
        )
    }

    private func scheduleThrottledWatchAuditRetry(watchID: UUID, rootURL: URL, lastAuditAt: Date?) {
        guard let lastAuditAt else { return }

        watchAuditRetryTasks[watchID]?.cancel()
        let delay = max(
            0.25,
            DirectoryWatchAuditThrottle.minAuditInterval - Date().timeIntervalSince(lastAuditAt) + 0.05
        )

        watchAuditRetryTasks[watchID] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            watchAuditRetryTasks.removeValue(forKey: watchID)

            if pendingWatchAuditNeedsFull.contains(watchID) {
                pendingWatchAuditNeedsFull.remove(watchID)
                pendingWatchAuditChanges.removeValue(forKey: watchID)
                runWatchAudit(watchID: watchID, rootURL: rootURL, force: true)
                return
            }

            guard let pendingPaths = pendingWatchAuditChanges.removeValue(forKey: watchID), !pendingPaths.isEmpty else {
                return
            }

            runWatchAudit(
                watchID: watchID,
                rootURL: rootURL,
                force: false,
                changedRelativePaths: pendingPaths
            )
        }
    }

    private func cancelWatchAudit(watchID: UUID) {
        watchAuditTasks[watchID]?.cancel()
        watchAuditTasks.removeValue(forKey: watchID)
        directoryWatchRuntime.isAuditing.remove(watchID)
        pendingWatchAuditChanges.removeValue(forKey: watchID)
        pendingWatchAuditNeedsFull.remove(watchID)
        watchAuditRetryTasks[watchID]?.cancel()
        watchAuditRetryTasks.removeValue(forKey: watchID)
    }

    private func cancelAllWatchAudits() {
        for task in watchAuditTasks.values {
            task.cancel()
        }
        watchAuditTasks.removeAll()
        directoryWatchRuntime.isAuditing.removeAll()
        pendingWatchAuditChanges.removeAll()
        pendingWatchAuditNeedsFull.removeAll()
        for task in watchAuditRetryTasks.values {
            task.cancel()
        }
        watchAuditRetryTasks.removeAll()
    }

    func workspaceStatusNeedsAttentionCount() -> Int {
        guard settings.directoryWatchEnabled else { return 0 }
        let activeIDs = Set(activeWatchedDirectoryEntries().map(\.id))
        return directoryWatchRuntime.statusByWatchID
            .filter { activeIDs.contains($0.key) }
            .map(\.value)
            .filter { WorkspaceWatchStatusDegrade.countsAsAttention($0) }
            .count
    }

    func workspaceStatusMenuTitle() -> String? {
        let count = workspaceStatusNeedsAttentionCount()
        guard count > 0 else { return nil }
        return OffsendStrings.menuWorkspaceStatusNeedsAttention(count)
    }

    func workspaceStatusMenuEntries() -> [WorkspaceStatusMenuEntry] {
        guard settings.directoryWatchEnabled else { return [] }
        let activeIDs = Set(activeWatchedDirectoryEntries().map(\.id))
        let sources = settings.watchedDirectories.map {
            WorkspaceStatusMenuEntry.Source(
                watchID: $0.id,
                resolvedPath: $0.resolvedPath,
                displayName: $0.displayName
            )
        }

        return WorkspaceStatusMenuEntry.attentionEntries(
            from: sources,
            statusByWatchID: directoryWatchRuntime.statusByWatchID,
            activeWatchIDs: activeIDs
        )
    }

    func activeWatchedDirectoryEntries() -> [WatchedDirectory] {
        DirectoryWatchLimits.activeEntries(
            from: settings.watchedDirectories,
            workspaceAuditFull: tariffFeatures.workspaceAuditFull
        )
    }

    func persistWatchSettings() {
        try? store.saveSettings(settings)
    }

    private func handleWatchAuditResult(
        watchID: UUID,
        result: AIWorkspacePrivacyAuditResult,
        previousStatus: AIWorkspacePrivacyAuditStatus?,
        previousResultAtStart: AIWorkspacePrivacyAuditResult?,
        auditStartedAt: Date
    ) {
        guard settings.watchedDirectories.contains(where: { $0.id == watchID }) else { return }

        if let index = settings.watchedDirectories.firstIndex(where: { $0.id == watchID }),
           let lastAuditAt = settings.watchedDirectories[index].lastAuditAt,
           lastAuditAt > auditStartedAt {
            refreshMenuBarStatusItem()
            return
        }

        if result.isDirectoryUnavailable {
            handleUnavailableWatchAuditResult(watchID: watchID, result: result)
            return
        }

        let previousResult = previousResultAtStart
        directoryWatchRuntime.statusByWatchID[watchID] = result.status
        directoryWatchRuntime.lastResultByWatchID[watchID] = result

        if let index = settings.watchedDirectories.firstIndex(where: { $0.id == watchID }) {
            settings.watchedDirectories[index].lastAuditAt = Date()
            settings.watchedDirectories[index].lastStatus = result.status.rawValue
            settings.watchedDirectories[index].resolvedPath = WatchedDirectoryPathMatcher.standardizedPath(for: result.directoryURL)
            persistWatchSettings()
        }

        if settings.directoryWatchNotifyOnDegrade {
            let addedExposedPaths = previousResult.map {
                AIWorkspacePrivacyAuditDelta.compute(from: $0, to: result).addedExposedRelativePaths
            } ?? []
            if WorkspaceWatchStatusDegrade.shouldNotify(
                from: previousStatus,
                to: result.status,
                workspaceAuditFull: tariffFeatures.workspaceAuditFull,
                addedExposedRelativePaths: addedExposedPaths
            ) {
                analytics.track(
                    .watchStatusDegraded(
                        fromStatus: (previousStatus ?? .pass).rawValue,
                        toStatus: result.status.rawValue
                    )
                )
                postWorkspaceDegradedNotification(
                    watchID: watchID,
                    directoryURL: result.directoryURL,
                    status: result.status,
                    auditResult: result,
                    previousResult: previousResult
                )
            }
        }

        refreshMenuBarStatusItem()
    }

    private func handleUnavailableWatchAuditResult(
        watchID: UUID,
        result: AIWorkspacePrivacyAuditResult
    ) {
        let wasUnavailable = directoryWatchRuntime.unavailableWatchIDs.contains(watchID)
        directoryWatchRuntime.unavailableWatchIDs.insert(watchID)
        directoryWatchRuntime.statusByWatchID.removeValue(forKey: watchID)
        directoryWatchRuntime.lastResultByWatchID.removeValue(forKey: watchID)

        if let index = settings.watchedDirectories.firstIndex(where: { $0.id == watchID }) {
            settings.watchedDirectories[index].lastAuditAt = Date()
            settings.watchedDirectories[index].lastStatus = nil
            persistWatchSettings()
        }

        if settings.directoryWatchNotifyOnDegrade, !wasUnavailable {
            postWorkspaceUnavailableNotification(
                watchID: watchID,
                directoryURL: result.directoryURL
            )
        }

        reloadDirectoryWatch(runInitialAudits: false)
    }

    func applyWorkspaceWatchFixFromNotification(watchID: UUID) {
        guard let entry = settings.watchedDirectories.first(where: { $0.id == watchID }),
              let path = entry.resolvedPath else {
            return
        }

        let rootURL = URL(fileURLWithPath: path)
        let configuration = directoryCheckAuditConfiguration()
        let auditResult = directoryWatchRuntime.lastResultByWatchID[watchID]
            ?? AIWorkspacePrivacyAuditor().audit(directoryURL: rootURL, configuration: configuration)

        let fixItems = AIWorkspacePrivacyFixPlanner.fixItems(for: auditResult, configuration: configuration)
        guard !fixItems.isEmpty else {
            openDirectoryCheckForWatch(watchID: watchID, source: "notification")
            return
        }

        let selection = AIWorkspacePrivacyFixPlanner.defaultSelection(for: fixItems, result: auditResult)
        let fixResult = AIWorkspacePrivacyFixer().fix(
            result: auditResult,
            configuration: configuration,
            selection: selection
        )

        if fixResult.didChangeFiles {
            lastStatusMessage = OffsendStrings.notificationWorkspaceFixApplied(
                fixResult.createdRelativePaths.count + fixResult.updatedRelativePaths.count,
                rootURL.lastPathComponent
            )
        } else if !fixResult.errors.isEmpty {
            lastStatusMessage = fixResult.errors.map(\.message).joined(separator: "\n")
        }

        runWatchAudit(watchID: watchID, rootURL: rootURL, force: true)
        openDirectoryCheckForWatch(watchID: watchID, source: "notification_fix")
    }

    private func postWorkspaceDegradedNotification(
        watchID: UUID,
        directoryURL: URL,
        status: AIWorkspacePrivacyAuditStatus,
        auditResult: AIWorkspacePrivacyAuditResult,
        previousResult: AIWorkspacePrivacyAuditResult?
    ) {
        let content = UNMutableNotificationContent()
        content.title = OffsendStrings.notificationWorkspaceDegradedTitle
        let statusLabel = statusTitle(for: status)
        let exposedSummary = exposedPathsNotificationSummary(
            auditResult: auditResult,
            previousResult: previousResult
        )
        if let exposedSummary {
            content.body = OffsendStrings.notificationWorkspaceDegradedBodyWithExposed(
                directoryURL.lastPathComponent,
                statusLabel,
                exposedSummary
            )
        } else {
            content.body = OffsendStrings.notificationWorkspaceDegradedBody(
                directoryURL.lastPathComponent,
                statusLabel
            )
        }
        content.categoryIdentifier = Self.workspaceDegradedNotificationCategoryID
        content.userInfo = [
            "watchID": watchID.uuidString,
            "directoryPath": directoryURL.path,
            "openDirectoryCheck": "1"
        ]

        let request = UNNotificationRequest(
            identifier: "workspace-degrade-\(watchID.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func postWorkspaceUnavailableNotification(
        watchID: UUID,
        directoryURL: URL
    ) {
        let content = UNMutableNotificationContent()
        content.title = OffsendStrings.notificationWorkspaceUnavailableTitle
        content.body = OffsendStrings.notificationWorkspaceUnavailableBody(directoryURL.lastPathComponent)
        content.categoryIdentifier = Self.workspaceUnavailableNotificationCategoryID
        content.userInfo = [
            "watchID": watchID.uuidString,
            "directoryPath": directoryURL.path,
            "directoryUnavailable": "1"
        ]

        let request = UNNotificationRequest(
            identifier: "workspace-unavailable-\(watchID.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func exposedPathsNotificationSummary(
        auditResult: AIWorkspacePrivacyAuditResult,
        previousResult: AIWorkspacePrivacyAuditResult?
    ) -> String? {
        if let previousResult {
            let delta = AIWorkspacePrivacyAuditDelta.compute(from: previousResult, to: auditResult)
            return WorkspaceWatchNotificationFormatter.exposedPathsSummary(from: delta)
                ?? WorkspaceWatchNotificationFormatter.exposedPathsSummary(from: auditResult)
        }
        return WorkspaceWatchNotificationFormatter.exposedPathsSummary(from: auditResult)
    }

    static let workspaceDegradedNotificationCategoryID = "workspace-degraded"
    static let workspaceUnavailableNotificationCategoryID = "workspace-unavailable"

    func registerWorkspaceWatchNotificationCategories() {
        var degradedActions: [UNNotificationAction] = [
            UNNotificationAction(
                identifier: "open",
                title: OffsendStrings.notificationWorkspaceOpenAction,
                options: [.foreground]
            )
        ]

        degradedActions.insert(
            UNNotificationAction(
                identifier: "fix",
                title: OffsendStrings.notificationWorkspaceFixAction,
                options: [.foreground]
            ),
            at: 0
        )

        let degradedCategory = UNNotificationCategory(
            identifier: Self.workspaceDegradedNotificationCategoryID,
            actions: degradedActions,
            intentIdentifiers: [],
            options: []
        )

        let unavailableCategory = UNNotificationCategory(
            identifier: Self.workspaceUnavailableNotificationCategoryID,
            actions: [
                UNNotificationAction(
                    identifier: "openSettings",
                    title: OffsendStrings.notificationWorkspaceOpenSettingsAction,
                    options: [.foreground]
                )
            ],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([degradedCategory, unavailableCategory])
    }

    private func statusTitle(for status: AIWorkspacePrivacyAuditStatus) -> String {
        switch status {
        case .pass: OffsendStrings.directoryCheckStatusPass
        case .warning: OffsendStrings.directoryCheckStatusWarning
        case .fail: OffsendStrings.directoryCheckStatusFail
        }
    }

    private func requestNotificationAuthorizationIfNeeded() {
        registerWorkspaceWatchNotificationCategories()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}

