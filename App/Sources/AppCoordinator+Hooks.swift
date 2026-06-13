import AppKit
import Foundation
import OffsendRuntime
import StorageCore

enum HookedRepositoryDisplayStatus: String, Sendable {
    case installed
    case missing
    case modified
    case unavailable
}

extension AppCoordinator {
    var offsendCLIExecutablePath: String? {
        OffsendCLILocator.resolvedExecutablePath()
    }

    var hookedRepositoryInstallCommand: String? {
        guard let cliPath = offsendCLIExecutablePath else { return nil }
        return "\(Self.shellQuote(cliPath)) hook install --cli-path \(Self.shellQuote(cliPath))"
    }

    func refreshHookedRepositoryStatuses() {
        let manager = HookManager()
        var updated = settings.hookedRepositories

        for index in updated.indices {
            guard let url = try? resolveHookedRepositoryURL(updated[index]) else {
                updated[index].hookStatus = HookedRepositoryDisplayStatus.unavailable.rawValue
                continue
            }

            do {
                let report = try manager.status(repositoryPath: url, hookType: hookType(for: updated[index]))
                updated[index].hookStatus = displayStatus(for: report.state).rawValue
                updated[index].resolvedPath = report.repositoryPath
            } catch {
                updated[index].hookStatus = HookedRepositoryDisplayStatus.unavailable.rawValue
            }
        }

        settings.hookedRepositories = updated
        saveSettings()
    }

    @discardableResult
    func addHookedRepository(url: URL) -> Bool {
        let gitResolver = GitRepositoryResolver()
        let repositoryRoot: URL
        do {
            repositoryRoot = try gitResolver.repositoryRoot(startingAt: url)
        } catch {
            lastStatusMessage = OffsendStrings.settingsHooksErrorNotGitRepository
            return false
        }

        let standardized = repositoryRoot.standardizedFileURL
        if HookedRepositoryPathMatcher.firstIndex(in: settings.hookedRepositories, matching: standardized) != nil {
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
            let projectConfig = try? ProjectConfigLoader().load(from: standardized)
            let defaults = OptionsResolver.defaultsForHookedRepository(from: projectConfig)
            let entry = HookedRepository(
                displayName: standardized.lastPathComponent,
                bookmarkData: bookmark,
                resolvedPath: WatchedDirectoryPathMatcher.standardizedPath(for: standardized),
                failPolicy: defaults.failPolicy,
                includePolicyCheck: defaults.includePolicyCheck,
                hookStatus: HookedRepositoryDisplayStatus.missing.rawValue
            )
            settings.hookedRepositories.append(entry)
            saveSettings()
            refreshHookedRepositoryStatuses()
            return true
        } catch {
            lastStatusMessage = error.localizedDescription
            return false
        }
    }

    func removeHookedRepository(id: UUID) {
        settings.hookedRepositories.removeAll { $0.id == id }
        saveSettings()
    }

    func installHook(for id: UUID, force: Bool = false) -> Bool {
        guard let index = settings.hookedRepositories.firstIndex(where: { $0.id == id }),
              let repositoryURL = try? resolveHookedRepositoryURL(settings.hookedRepositories[index]),
              let cliPath = offsendCLIExecutablePath else {
            lastStatusMessage = OffsendStrings.settingsHooksErrorCliNotFound
            return false
        }

        let entry = settings.hookedRepositories[index]
        let manager = HookManager()
        let projectConfig = try? ProjectConfigLoader().load(from: repositoryURL)
        let resolved = OptionsResolver.resolveHookOptions(
            overrides: CLIHookOverrides(
                hookType: entry.hookType,
                policySpecified: true,
                policyValue: entry.includePolicyCheck,
                failOn: entry.failPolicy
            ),
            projectConfig: projectConfig
        )

        do {
            _ = try manager.install(
                HookInstallOptions(
                    repositoryPath: repositoryURL,
                    hookType: resolved.hookType,
                    failPolicy: resolved.failPolicy,
                    includePolicyCheck: resolved.includePolicyCheck,
                    force: force,
                    cliExecutablePath: cliPath
                )
            )
            settings.hookedRepositories[index].installedAt = Date()
            settings.hookedRepositories[index].hookStatus = HookedRepositoryDisplayStatus.installed.rawValue
            settings.hookedRepositories[index].resolvedPath = WatchedDirectoryPathMatcher.standardizedPath(for: repositoryURL)
            saveSettings()
            lastStatusMessage = OffsendStrings.settingsHooksInstalled(entry.displayName ?? repositoryURL.lastPathComponent)
            return true
        } catch let error as HookManagerError {
            lastStatusMessage = message(for: error)
            refreshHookedRepositoryStatuses()
            return false
        } catch {
            lastStatusMessage = error.localizedDescription
            return false
        }
    }

    func uninstallHook(for id: UUID, force: Bool = false) -> Bool {
        guard let index = settings.hookedRepositories.firstIndex(where: { $0.id == id }),
              let repositoryURL = try? resolveHookedRepositoryURL(settings.hookedRepositories[index]) else {
            lastStatusMessage = OffsendStrings.settingsHooksErrorUnavailable
            return false
        }

        let manager = HookManager()
        do {
            try manager.uninstall(repositoryPath: repositoryURL, hookType: hookType(for: settings.hookedRepositories[index]), force: force)
            settings.hookedRepositories[index].installedAt = nil
            settings.hookedRepositories[index].hookStatus = HookedRepositoryDisplayStatus.missing.rawValue
            saveSettings()
            lastStatusMessage = OffsendStrings.settingsHooksUninstalled
            return true
        } catch let error as HookManagerError {
            lastStatusMessage = message(for: error)
            refreshHookedRepositoryStatuses()
            return false
        } catch {
            lastStatusMessage = error.localizedDescription
            return false
        }
    }

    func updateHookedRepositoryPolicy(id: UUID, includePolicyCheck: Bool) {
        guard let index = settings.hookedRepositories.firstIndex(where: { $0.id == id }) else { return }
        settings.hookedRepositories[index].includePolicyCheck = includePolicyCheck
        saveSettings()
        reinstallHookIfNeeded(for: id)
    }

    func updateHookedRepositoryFailPolicy(id: UUID, failPolicy: CheckFailPolicy) {
        guard let index = settings.hookedRepositories.firstIndex(where: { $0.id == id }) else { return }
        settings.hookedRepositories[index].failPolicy = failPolicy.rawValue
        saveSettings()
        reinstallHookIfNeeded(for: id)
    }

    func hookedRepositoryInstallCommand(for entry: HookedRepository) -> String? {
        guard let cliPath = offsendCLIExecutablePath,
              let path = entry.resolvedPath else { return nil }
        return "\(Self.shellQuote(cliPath)) hook install --path \(Self.shellQuote(path)) --cli-path \(Self.shellQuote(cliPath))"
    }

    func copyHookedRepositoryInstallCommand(for entry: HookedRepository) {
        guard let command = hookedRepositoryInstallCommand(for: entry) else {
            lastStatusMessage = OffsendStrings.settingsHooksErrorCliNotFound
            return
        }
        clipboardService.writeString(command)
        lastStatusMessage = OffsendStrings.settingsHooksCopiedInstallCommand
    }

    func openHookedRepositoryInFinder(id: UUID) {
        guard let url = try? resolveHookedRepositoryURL(id: id) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    func displayStatus(for entry: HookedRepository) -> HookedRepositoryDisplayStatus {
        guard let raw = entry.hookStatus,
              let status = HookedRepositoryDisplayStatus(rawValue: raw) else {
            return .missing
        }
        return status
    }

    func projectConfigPath(for entry: HookedRepository) -> String? {
        guard let url = try? resolveHookedRepositoryURL(entry) else { return nil }
        return ProjectConfigLoader().configURL(for: url)?.path
    }

    private func reinstallHookIfNeeded(for id: UUID) {
        guard let index = settings.hookedRepositories.firstIndex(where: { $0.id == id }),
              settings.hookedRepositories[index].hookStatus == HookedRepositoryDisplayStatus.installed.rawValue else {
            return
        }
        _ = installHook(for: id, force: false)
    }

    private func resolveHookedRepositoryURL(_ entry: HookedRepository) throws -> URL {
        let resolution = try WatchedDirectoryBookmark.resolve(entry.bookmarkData)
        defer { resolution.url.stopAccessingSecurityScopedResource() }
        return resolution.url.standardizedFileURL
    }

    private func resolveHookedRepositoryURL(id: UUID) throws -> URL {
        guard let entry = settings.hookedRepositories.first(where: { $0.id == id }) else {
            throw WatchedDirectoryBookmark.Error.accessDenied
        }
        return try resolveHookedRepositoryURL(entry)
    }

    private func hookType(for entry: HookedRepository) -> HookType {
        HookType(rawValue: entry.hookType) ?? .preCommit
    }

    private func failPolicy(for entry: HookedRepository) -> CheckFailPolicy {
        CheckFailPolicy(rawValue: entry.failPolicy) ?? .block
    }

    private func displayStatus(for state: HookInstallationState) -> HookedRepositoryDisplayStatus {
        switch state {
        case .installed:
            return .installed
        case .notInstalled:
            return .missing
        case .modified:
            return .modified
        }
    }

    private func message(for error: HookManagerError) -> String {
        switch error {
        case .notARepository:
            return OffsendStrings.settingsHooksErrorNotGitRepository
        case .hookAlreadyInstalled:
            return OffsendStrings.settingsHooksErrorHookAlreadyExists
        case .hookNotInstalled:
            return OffsendStrings.settingsHooksErrorHookNotInstalled
        case .hookModified:
            return OffsendStrings.settingsHooksErrorHookModified
        case .cliNotFound:
            return OffsendStrings.settingsHooksErrorCliNotFound
        case .writeFailed(_, let message):
            return message
        }
    }

    private static func shellQuote(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_./:-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
