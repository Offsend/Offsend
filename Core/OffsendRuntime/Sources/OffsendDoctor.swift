import Foundation
import StorageCore
import WorkspacePolicyCore

public enum DoctorCheckStatus: String, Sendable, Equatable {
    case ok
    case warn
    case fail
}

public struct DoctorCheck: Equatable, Sendable {
    public let name: String
    public let status: DoctorCheckStatus
    public let message: String

    public init(name: String, status: DoctorCheckStatus, message: String) {
        self.name = name
        self.status = status
        self.message = message
    }
}

public struct DoctorReport: Equatable, Sendable {
    public let checks: [DoctorCheck]
    /// Ranked setup commands (e.g. `offsend init`), for interactive follow-up.
    public let suggestedActions: [String]

    public var isHealthy: Bool {
        !checks.contains { $0.status == .fail }
    }

    public init(checks: [DoctorCheck], suggestedActions: [String] = []) {
        self.checks = checks
        self.suggestedActions = suggestedActions
    }

    /// First suggested shell command (comment stripped).
    public var primarySuggestedCommand: String? {
        guard let action = suggestedActions.first else { return nil }
        return Self.command(from: action)
    }

    public static func command(from action: String) -> String {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = trimmed.firstIndex(of: "#") {
            return trimmed[..<hash].trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}

public struct OffsendDoctor: Sendable {
    private let fileManager: FileManager
    private let gitExecutable: String

    public init(
        fileManager: FileManager = .default,
        gitExecutable: String? = nil
    ) {
        self.fileManager = fileManager
        self.gitExecutable = gitExecutable ?? ExecutableLocator.defaultGitExecutable(fileManager: fileManager)
    }

    public func run(context: OffsendRuntimeContext? = try? OffsendRuntimeContext.load()) -> DoctorReport {
        var checks: [DoctorCheck] = []

        if let context {
            checks.append(
                DoctorCheck(
                    name: "settings",
                    status: .ok,
                    message: "Loaded \(context.settings.enabledDetectors.count) enabled detector(s) from local settings."
                )
            )
        } else {
            checks.append(
                DoctorCheck(
                    name: "settings",
                    status: .fail,
                    message: "Could not load Offsend settings from \(LocalStoreDirectory.defaultURL().path)."
                )
            )
        }

        if let cliPath = OffsendCLILocator.resolvedExecutablePath() {
            checks.append(
                DoctorCheck(
                    name: "cli",
                    status: .ok,
                    message: cliPath
                )
            )
        } else {
            checks.append(
                DoctorCheck(
                    name: "cli",
                    status: .fail,
                    message: "offsend executable not found in PATH\(Self.cliPathSuffix)."
                )
            )
        }

        #if os(macOS)
        if let bundledCLIPath = bundledAppCLIPath() {
            let terminalStatus = CLIPathInstaller(bundledCLIPath: bundledCLIPath, fileManager: fileManager).status()
            checks.append(
                DoctorCheck(
                    name: "terminal-command",
                    status: doctorStatus(
                        for: terminalStatus.state,
                        shadowingManagedInstallPath: terminalStatus.shadowingManagedInstallPath
                    ),
                    message: terminalCommandMessage(for: terminalStatus)
                )
            )
        }
        #endif

        if fileManager.isExecutableFile(atPath: gitExecutable) {
            checks.append(
                DoctorCheck(
                    name: "git",
                    status: .ok,
                    message: gitExecutable
                )
            )
        } else {
            checks.append(
                DoctorCheck(
                    name: "git",
                    status: .fail,
                    message: "git executable not found at \(gitExecutable)."
                )
            )
        }

        let configLoader = ProjectConfigLoader(fileManager: fileManager)
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        checks.append(projectConfigCheck(loader: configLoader, directory: cwd))
        checks.append(contentsOf: ignorePolicyChecks(loader: configLoader, directory: cwd))

        let installer = AIEditorHookInstaller(fileManager: fileManager)
        var installedCount = 0
        var anyAIHookInstalled = false
        for target in AIEditorHookTarget.allCases {
            let status = installer.status(target: target, repositoryPath: cwd)
            // Absent AI hooks are optional — only report when present (ok) or broken (warn).
            if status.broken {
                var details: [String] = []
                let promptURL = cwd.appendingPathComponent(AIEditorHookInstaller.wrapperRelativePath)
                let promptIssue = installer.validateWrapper(at: promptURL)
                if promptIssue != .ok {
                    details.append(
                        AIEditorHookInstaller.wrapperValidationMessage(promptIssue, path: promptURL.path)
                    )
                }
                if let contents = try? String(contentsOf: URL(fileURLWithPath: status.configPath), encoding: .utf8) {
                    if AIEditorHookInstaller.configTextReferences(
                        contents,
                        relativePath: AIEditorHookInstaller.readWrapperRelativePath
                    ) {
                        let readURL = cwd.appendingPathComponent(AIEditorHookInstaller.readWrapperRelativePath)
                        let readIssue = installer.validateWrapper(at: readURL)
                        if readIssue != .ok {
                            details.append(
                                AIEditorHookInstaller.wrapperValidationMessage(readIssue, path: readURL.path)
                            )
                        }
                    }
                    if AIEditorHookInstaller.configTextReferences(
                        contents,
                        relativePath: AIEditorHookInstaller.shellWrapperRelativePath
                    ) {
                        let shellURL = cwd.appendingPathComponent(AIEditorHookInstaller.shellWrapperRelativePath)
                        let shellIssue = installer.validateWrapper(at: shellURL)
                        if shellIssue != .ok {
                            details.append(
                                AIEditorHookInstaller.wrapperValidationMessage(shellIssue, path: shellURL.path)
                            )
                        }
                    }
                    if AIEditorHookInstaller.configTextReferences(
                        contents,
                        relativePath: AIEditorHookInstaller.mcpWrapperRelativePath
                    ) {
                        let mcpURL = cwd.appendingPathComponent(AIEditorHookInstaller.mcpWrapperRelativePath)
                        let mcpIssue = installer.validateWrapper(at: mcpURL)
                        if mcpIssue != .ok {
                            details.append(
                                AIEditorHookInstaller.wrapperValidationMessage(mcpIssue, path: mcpURL.path)
                            )
                        }
                    }
                }
                if details.isEmpty {
                    details.append("wrapper missing or not executable")
                }
                checks.append(
                    DoctorCheck(
                        name: "ai-hook-\(target.rawValue)",
                        status: .warn,
                        message: "Configured at \(status.configPath) but wrapper invalid: \(details.joined(separator: "; ")). Re-run: offsend hook install --target \(target.rawValue)"
                    )
                )
                installedCount += 1
                anyAIHookInstalled = true
            } else if status.installed {
                checks.append(
                    DoctorCheck(
                        name: "ai-hook-\(target.rawValue)",
                        status: .ok,
                        message: status.configPath
                    )
                )
                installedCount += 1
                anyAIHookInstalled = true
            }
        }

        if anyAIHookInstalled {
            let promptURL = cwd.appendingPathComponent(AIEditorHookInstaller.wrapperRelativePath)
            let promptValidation = installer.validateWrapper(at: promptURL)
            if promptValidation != .ok {
                checks.append(
                    DoctorCheck(
                        name: "ai-wrapper-prompt",
                        status: .warn,
                        message: AIEditorHookInstaller.wrapperValidationMessage(
                            promptValidation,
                            path: promptURL.path
                        )
                    )
                )
            } else {
                checks.append(
                    DoctorCheck(
                        name: "ai-wrapper-prompt",
                        status: .ok,
                        message: "\(promptURL.path) (v\(AIEditorHookInstaller.managedVersion))"
                    )
                )
            }

            let readURL = cwd.appendingPathComponent(AIEditorHookInstaller.readWrapperRelativePath)
            if fileManager.fileExists(atPath: readURL.path) {
                let readValidation = installer.validateWrapper(at: readURL)
                if readValidation != .ok {
                    checks.append(
                        DoctorCheck(
                            name: "ai-wrapper-read",
                            status: .warn,
                            message: AIEditorHookInstaller.wrapperValidationMessage(
                                readValidation,
                                path: readURL.path
                            )
                        )
                    )
                } else {
                    checks.append(
                        DoctorCheck(
                            name: "ai-wrapper-read",
                            status: .ok,
                            message: "\(readURL.path) (v\(AIEditorHookInstaller.managedVersion))"
                        )
                    )
                }
            }

            let shellURL = cwd.appendingPathComponent(AIEditorHookInstaller.shellWrapperRelativePath)
            if fileManager.fileExists(atPath: shellURL.path) {
                let shellValidation = installer.validateWrapper(at: shellURL)
                if shellValidation != .ok {
                    checks.append(
                        DoctorCheck(
                            name: "ai-wrapper-shell",
                            status: .warn,
                            message: AIEditorHookInstaller.wrapperValidationMessage(
                                shellValidation,
                                path: shellURL.path
                            )
                        )
                    )
                } else {
                    checks.append(
                        DoctorCheck(
                            name: "ai-wrapper-shell",
                            status: .ok,
                            message: "\(shellURL.path) (v\(AIEditorHookInstaller.managedVersion))"
                        )
                    )
                }
            }

            let mcpURL = cwd.appendingPathComponent(AIEditorHookInstaller.mcpWrapperRelativePath)
            if fileManager.fileExists(atPath: mcpURL.path) {
                let mcpValidation = installer.validateWrapper(at: mcpURL)
                if mcpValidation != .ok {
                    checks.append(
                        DoctorCheck(
                            name: "ai-wrapper-mcp",
                            status: .warn,
                            message: AIEditorHookInstaller.wrapperValidationMessage(
                                mcpValidation,
                                path: mcpURL.path
                            )
                        )
                    )
                } else {
                    checks.append(
                        DoctorCheck(
                            name: "ai-wrapper-mcp",
                            status: .ok,
                            message: "\(mcpURL.path) (v\(AIEditorHookInstaller.managedVersion))"
                        )
                    )
                }
            }

            // Shell-gate is on by default for Cursor/Claude; warn when an install omits it.
            let missingShellGate = AIEditorHookTarget.allCases.filter { target in
                guard AIEditorHookInstaller.supportsFileGates(target) else { return false }
                let status = installer.status(target: target, repositoryPath: cwd)
                return status.installed && !status.shellGate
            }
            if !missingShellGate.isEmpty {
                let names = missingShellGate.map(\.rawValue).joined(separator: ", ")
                checks.append(
                    DoctorCheck(
                        name: "ai-shell-gate",
                        status: .warn,
                        message: "Shell gate not installed for \(names). Agents can still read sensitive files via shell (cat/grep/sed). Re-run: offsend hook install --target cursor|claude (shell-gate is on by default; use --no-shell-gate to opt out)"
                    )
                )
            }

            let missingMCPGate = AIEditorHookTarget.allCases.filter { target in
                guard AIEditorHookInstaller.supportsFileGates(target) else { return false }
                let status = installer.status(target: target, repositoryPath: cwd)
                return status.installed && !status.mcpGate
            }
            if !missingMCPGate.isEmpty {
                let names = missingMCPGate.map(\.rawValue).joined(separator: ", ")
                checks.append(
                    DoctorCheck(
                        name: "ai-mcp-gate",
                        status: .warn,
                        message: "MCP gate not installed for \(names). Tool payloads can bypass file/shell gates. Re-run: offsend hook install --target cursor|claude (mcp-gate is on by default; use --no-mcp-gate to opt out)"
                    )
                )
            }

            let missingSubagentGate = AIEditorHookTarget.allCases.filter { target in
                guard AIEditorHookInstaller.supportsSubagentGate(target) else { return false }
                let status = installer.status(target: target, repositoryPath: cwd)
                return status.installed && !status.subagentGate
            }
            if !missingSubagentGate.isEmpty {
                checks.append(
                    DoctorCheck(
                        name: "ai-subagent-gate",
                        status: .warn,
                        message: "Subagent gate not installed for cursor. Task prompts to subagents are unchecked. Re-run: offsend hook install --target cursor (subagent-gate is on by default; use --no-subagent-gate to opt out)"
                    )
                )
            }

            let subagentURL = cwd.appendingPathComponent(AIEditorHookInstaller.subagentWrapperRelativePath)
            if fileManager.fileExists(atPath: subagentURL.path) {
                let subagentValidation = installer.validateWrapper(at: subagentURL)
                if subagentValidation != .ok {
                    checks.append(
                        DoctorCheck(
                            name: "ai-wrapper-subagent",
                            status: .warn,
                            message: AIEditorHookInstaller.wrapperValidationMessage(
                                subagentValidation,
                                path: subagentURL.path
                            )
                        )
                    )
                } else {
                    checks.append(
                        DoctorCheck(
                            name: "ai-wrapper-subagent",
                            status: .ok,
                            message: "\(subagentURL.path) (v\(AIEditorHookInstaller.managedVersion))"
                        )
                    )
                }
            }
        }

        let home = ProcessInfo.processInfo.environment["HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? fileManager.homeDirectoryForCurrentUser
        let projectConfig = try? configLoader.load(from: cwd)
        let mcpInventory = OffsendMCPInventory(fileManager: fileManager).collect(
            projectRoot: cwd,
            homeDirectory: home,
            mcpConfig: projectConfig?.context?.mcp
        )
        if mcpInventory.servers.isEmpty {
            checks.append(
                DoctorCheck(
                    name: "mcp-inventory",
                    status: .ok,
                    message: "No MCP servers configured in project/user Cursor/Claude configs"
                )
            )
        } else {
            let risk = mcpInventory.servers.filter(\.highRisk).count
            var message = "\(mcpInventory.servers.count) MCP server(s)"
            if risk > 0 { message += ", \(risk) high-risk" }
            if mcpInventory.policyMode == nil {
                message += "; context.mcp policy unset — add context.mcp to .offsend.yml"
                checks.append(DoctorCheck(name: "mcp-inventory", status: .warn, message: message))
            } else {
                message += "; policy: \(mcpInventory.policyMode ?? "observe")"
                checks.append(DoctorCheck(name: "mcp-inventory", status: .ok, message: message))
            }
        }

        if let context {
            let history = OffsendShowService(context: context).run(directoryURL: cwd).history
            if history.filesScanned > 0 {
                checks.append(
                    DoctorCheck(
                        name: "agent-history",
                        status: .warn,
                        message: "\(history.filesScanned) local agent transcript file(s) found. Run: offsend history audit"
                    )
                )
            } else {
                checks.append(
                    DoctorCheck(
                        name: "agent-history",
                        status: .ok,
                        message: "No project-scoped Cursor agent transcripts found"
                    )
                )
            }
        }

        checks.append(
            DoctorCheck(
                name: "ai-hooks",
                status: .ok,
                message: "\(installedCount)/\(AIEditorHookTarget.allCases.count) installed (optional)"
            )
        )

        let sealKeyURL = SealKeyPaths.defaultKeyURL(fileManager: fileManager)
        let sealKeyPath = sealKeyURL.path
        if fileManager.fileExists(atPath: sealKeyPath) {
            let namedCount = SealKeyPaths.countNamedKeys(fileManager: fileManager)
            var message = namedCount > 0
                ? "\(sealKeyPath) (+\(namedCount) named keys)"
                : sealKeyPath
            var status = DoctorCheckStatus.ok
            if let permissionWarning = SealKeyPaths.insecurePermissionWarning(
                at: sealKeyURL,
                fileManager: fileManager
            ) {
                status = .warn
                message = "\(message); \(permissionWarning)"
            }
            checks.append(
                DoctorCheck(
                    name: "seal-key",
                    status: status,
                    message: message
                )
            )
        } else if let envValue = ProcessInfo.processInfo.environment[SealKeyResolver.environmentVariable],
                  !envValue.isEmpty {
            checks.append(
                DoctorCheck(
                    name: "seal-key",
                    status: .ok,
                    message: "\(SealKeyResolver.environmentVariable) is set"
                )
            )
        } else {
            checks.append(
                DoctorCheck(
                    name: "seal-key",
                    status: .warn,
                    message: "No default seal key or \(SealKeyResolver.environmentVariable). Run: \(SealKeyPaths.defaultKeyInstallHint)"
                )
            )
        }

        let next = nextActionsCheck(
            cwd: cwd,
            configLoader: configLoader,
            installer: installer,
            context: context
        )
        checks.append(next.check)

        return DoctorReport(checks: checks, suggestedActions: next.actions)
    }

    /// Ranked setup hints: project config → AI boundary → shell/MCP gates → git hook.
    private func nextActionsCheck(
        cwd: URL,
        configLoader: ProjectConfigLoader,
        installer: AIEditorHookInstaller,
        context: OffsendRuntimeContext?
    ) -> (check: DoctorCheck, actions: [String]) {
        var actions: [String] = []

        if configLoader.configURL(for: cwd) == nil {
            actions.append("offsend init --template <stack>   # create .offsend.yml")
        } else if Self.needsIgnoreMaterialization(
            configLoader: configLoader,
            directory: cwd,
            fileManager: fileManager,
            gitResolver: GitRepositoryResolver(fileManager: fileManager, gitExecutable: gitExecutable)
        ) {
            actions.append("offsend sync   # materialize ignore files + hooks")
        }

        let showReport = context.map { OffsendShowService(context: $0).run(directoryURL: cwd) }
        if let show = showReport {
            let requiredPaths = Set(
                show.groups
                    .filter { $0.severity == AIWorkspacePrivacyRuleSeverity.required.rawValue }
                    .flatMap(\.relativePaths)
            )
            if !requiredPaths.isEmpty {
                actions.append(
                    "offsend protect   # hide \(requiredPaths.count) required path(s) from AI, then offsend show"
                )
            }
        }

        let gateTargets: [AIEditorHookTarget] = [.cursor, .claude]
        let installedWithoutShell = gateTargets.filter { target in
            let status = installer.status(target: target, repositoryPath: cwd)
            return status.installed && !status.shellGate
        }
        let installedWithoutMCP = gateTargets.filter { target in
            let status = installer.status(target: target, repositoryPath: cwd)
            return status.installed && !status.mcpGate
        }
        if !installedWithoutShell.isEmpty {
            actions.append(
                "offsend hook install --target \(installedWithoutShell[0].rawValue)   # add shell-gate (on by default)"
            )
        } else if !installedWithoutMCP.isEmpty {
            actions.append(
                "offsend hook install --target \(installedWithoutMCP[0].rawValue)   # add mcp-gate (on by default)"
            )
        } else {
            let cursorStatus = installer.status(target: .cursor, repositoryPath: cwd)
            if cursorStatus.installed, !cursorStatus.subagentGate {
                actions.append(
                    "offsend hook install --target cursor   # add subagent-gate (on by default)"
                )
            } else {
                let anyAI = AIEditorHookTarget.allCases.contains {
                    installer.status(target: $0, repositoryPath: cwd).installed
                }
                if !anyAI {
                    actions.append("offsend hook install   # prompt/read/shell/MCP/subagent gates + git pre-commit")
                }
            }
        }

        if let history = showReport?.history, history.filesScanned > 0 {
            actions.append("offsend history audit   # scan \(history.filesScanned) local agent transcript(s)")
        }

        let gitInstalled = (try? HookManager(fileManager: fileManager).isInstalled(repositoryPath: cwd)) ?? false
        if !gitInstalled, !actions.contains(where: { $0.contains("hook install") }) {
            actions.append("offsend hook install --target git   # pre-commit check --staged")
        }

        if actions.isEmpty {
            return (
                DoctorCheck(
                    name: "next-actions",
                    status: .ok,
                    message: "No urgent setup steps. Optional: offsend check --staged --policy"
                ),
                []
            )
        }

        let numbered = actions.enumerated().map { index, action in
            "\(index + 1). \(action)"
        }
        return (
            DoctorCheck(
                name: "next-actions",
                status: .warn,
                message: numbered.joined(separator: "\n")
            ),
            actions
        )
    }

    /// Fresh-clone detection: `.offsend.yml` exists but some managed AI ignore
    /// files (narrowed to `ignore.tools`) are not materialized locally —
    /// `offsend sync` fixes this.
    static func needsIgnoreMaterialization(
        configLoader: ProjectConfigLoader,
        directory: URL,
        fileManager: FileManager = .default,
        gitResolver: GitRepositoryResolver = GitRepositoryResolver()
    ) -> Bool {
        guard let config = (try? configLoader.load(from: directory)) ?? nil else { return false }
        let root = (try? gitResolver.repositoryRoot(startingAt: directory)) ?? directory
        let targets = OffsendIgnoreSyncService.managedIgnoreRelativePaths(tools: config.ignore?.toolIDs)
        guard !targets.isEmpty else { return false }
        return targets.contains { !fileManager.fileExists(atPath: root.appendingPathComponent($0).path) }
    }

    private func projectConfigCheck(loader: ProjectConfigLoader, directory: URL) -> DoctorCheck {
        guard let configURL = loader.configURL(for: directory) else {
            return DoctorCheck(
                name: "project-config",
                status: .warn,
                message: "No \(ProjectConfigLoader.filename) found for the current directory."
            )
        }

        do {
            guard let config = try loader.load(from: directory) else {
                return DoctorCheck(
                    name: "project-config",
                    status: .warn,
                    message: "No \(ProjectConfigLoader.filename) found for the current directory."
                )
            }
            let contents = try String(contentsOf: configURL, encoding: .utf8)
            let issues = ProjectConfigValidator.validateYAMLStructure(contents)
                + ProjectConfigValidator.validate(config)
            guard issues.isEmpty else {
                return DoctorCheck(
                    name: "project-config",
                    status: .warn,
                    message: "\(configURL.path) — \(issues.joined(separator: " "))"
                )
            }
            return DoctorCheck(name: "project-config", status: .ok, message: configURL.path)
        } catch let error as ProjectConfigLoaderError {
            return DoctorCheck(
                name: "project-config",
                status: .fail,
                message: projectConfigErrorMessage(error, path: configURL.path)
            )
        } catch {
            return DoctorCheck(
                name: "project-config",
                status: .fail,
                message: "\(configURL.path): \(error.localizedDescription)"
            )
        }
    }

    private func projectConfigErrorMessage(_ error: ProjectConfigLoaderError, path: String) -> String {
        switch error {
        case .unreadable(let path):
            return "Could not read \(path)."
        case .invalidYAML(let path, let message):
            return "Invalid YAML in \(path): \(message)"
        case .unsupportedVersion(let version):
            return "\(path): unsupported version \(version); expected 1."
        }
    }

    private func ignorePolicyChecks(loader: ProjectConfigLoader, directory: URL) -> [DoctorCheck] {
        guard let config = try? loader.load(from: directory) else { return [] }
        var checks: [DoctorCheck] = []

        let commitIgnore = config.ignore?.commitsIgnoreFiles ?? false
        let toolIDs = config.ignore?.toolIDs
        checks.append(
            DoctorCheck(
                name: "ignore-commit",
                status: .ok,
                message: commitIgnore
                    ? "ignore.commit: true — AI ignore files may be tracked in git."
                    : "ignore.commit: false — AI ignore files stay local (.gitignore)."
            )
        )

        let publishHooks = config.hooks?.publishesHooks ?? false
        checks.append(
            DoctorCheck(
                name: "hooks-publish",
                status: .ok,
                message: publishHooks
                    ? "hooks.publish: true — AI editor hooks may be committed."
                    : "hooks.publish: false — AI editor hooks stay local."
            )
        )

        if let patterns = config.ignore?.patterns, !patterns.isEmpty {
            let drift = OffsendManagedIgnoreDrift.findings(
                directoryURL: directory,
                patterns: patterns
            )
            if drift.isEmpty {
                checks.append(
                    DoctorCheck(
                        name: "ignore-sync",
                        status: .ok,
                        message: "Existing AI ignore files include managed patterns from .offsend.yml."
                    )
                )
            } else {
                let summary = drift.map { "\($0.relativePath) (-\($0.missingPatterns.count))" }.joined(separator: ", ")
                checks.append(
                    DoctorCheck(
                        name: "ignore-sync",
                        status: .warn,
                        message: "Managed ignore drift: \(summary). Run: offsend sync"
                    )
                )
            }
        }

        let resolver = GitRepositoryResolver(fileManager: fileManager, gitExecutable: gitExecutable)
        let repoRoot = try? resolver.repositoryRoot(startingAt: directory)
        let gitignoreService = OffsendGitignoreService(fileManager: fileManager)
        let excludeService = OffsendLocalGitExcludeService(fileManager: fileManager, gitResolver: resolver)
        let ignoreFilesSection = OffsendLocalGitExcludeService.ignoreFilesSection
        let gitignoreRoot = repoRoot ?? directory

        if commitIgnore {
            // Stale exclusion contradicts commit: true — files can never be added.
            if gitignoreService.hasSection(ignoreFilesSection, directoryURL: gitignoreRoot) {
                checks.append(
                    DoctorCheck(
                        name: "ignore-commit-conflict",
                        status: .warn,
                        message: "ignore.commit is true but .gitignore still hides AI ignore files. Run: offsend sync"
                    )
                )
            } else if excludeService.hasSection(ignoreFilesSection, repositoryURL: directory) {
                checks.append(
                    DoctorCheck(
                        name: "ignore-commit-conflict",
                        status: .warn,
                        message: "ignore.commit is true but .git/info/exclude still hides AI ignore files. Run: offsend sync"
                    )
                )
            }
        } else {
            if !gitignoreService.hasSection(ignoreFilesSection, directoryURL: gitignoreRoot) {
                checks.append(
                    DoctorCheck(
                        name: "ignore-commit-conflict",
                        status: .warn,
                        message: "ignore.commit is false but .gitignore does not list AI ignore files. Run: offsend sync"
                    )
                )
            }
            if let repoRoot {
                let ignorePaths = OffsendIgnoreSyncService.managedIgnoreRelativePaths(tools: toolIDs)
                    + OffsendIgnoreSyncService.managedRuleRelativePaths(tools: toolIDs)
                let tracked = (try? resolver.trackedRelativePaths(matching: ignorePaths, in: repoRoot)) ?? []
                if !tracked.isEmpty {
                    checks.append(
                        DoctorCheck(
                            name: "ignore-commit-conflict",
                            status: .warn,
                            message: "ignore.commit is false but git tracks: \(tracked.joined(separator: ", ")). Remove them with `git rm --cached <path>` to keep them local."
                        )
                    )
                }
            }
        }

        let driftedRules = OffsendPrepareService.driftedManagedRules(
            configuration: AIWorkspacePrivacyAuditConfiguration.default.filtered(tools: toolIDs),
            rootURL: repoRoot ?? directory,
            fileManager: fileManager
        )
        if !driftedRules.isEmpty {
            let paths = driftedRules.map(\.relativePath).joined(separator: ", ")
            checks.append(
                DoctorCheck(
                    name: "rules-drift",
                    status: .warn,
                    message: "Managed rule files were edited: \(paths). Offsend owns these files; run `offsend protect` to restore them and keep custom rules in separate files."
                )
            )
        }

        if !publishHooks, let repoRoot {
            let hookPaths = OffsendLocalGitExcludeService.allKnownHookRelativePaths
            let tracked = (try? resolver.trackedRelativePaths(matching: hookPaths, in: repoRoot)) ?? []
            if !tracked.isEmpty {
                checks.append(
                    DoctorCheck(
                        name: "hooks-local",
                        status: .warn,
                        message: "hooks.publish is false but git tracks: \(tracked.joined(separator: ", ")). Remove them with `git rm --cached <path>` to keep them local."
                    )
                )
            }
        }

        return checks
    }

    private static var cliPathSuffix: String {
        #if os(macOS)
        return " or Offsend.app Contents/Helpers."
        #else
        return "."
        #endif
    }

    #if os(macOS)
    private func bundledAppCLIPath() -> String? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/offsend").path,
            "/Applications/Offsend.app/Contents/Helpers/offsend",
            "\(NSHomeDirectory())/Applications/Offsend.app/Contents/Helpers/offsend"
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    private func doctorStatus(for state: CLIPathInstallationState, shadowingManagedInstallPath: String?) -> DoctorCheckStatus {
        if shadowingManagedInstallPath != nil {
            return .warn
        }

        switch state {
        case .installed, .availableViaHomebrew:
            return .ok
        case .notInstalled, .availableViaForeign, .targetBlocked, .brokenManagedLink:
            return .warn
        }
    }

    private func terminalCommandMessage(for status: CLIPathInstallationStatus) -> String {
        if let shadowingPath = status.shadowingManagedInstallPath {
            return "An older Offsend-managed install at \(shadowingPath) may shadow \(status.commandPath ?? "offsend") in terminals."
        }

        switch status.state {
        case .installed:
            return status.commandPath ?? status.installPath
        case .availableViaHomebrew:
            return "offsend is available through Homebrew at \(status.commandPath ?? "offsend")."
        case .availableViaForeign:
            return "offsend resolves to another executable at \(status.commandPath ?? "offsend")."
        case .targetBlocked:
            return "\(status.installPath) exists and is not an Offsend-managed symlink."
        case .brokenManagedLink:
            return "\(status.installPath) points to a moved or deleted Offsend.app. Reinstall the command from Settings."
        case .notInstalled:
            return "offsend is not installed in PATH. Install it from Settings → Hooks → CLI."
        }
    }
    #endif
}

public struct DoctorReporter: Sendable {
    public init() {}

    public func render(_ report: DoctorReport, format: CheckOutputFormat, useColor: Bool = false) -> String {
        switch format {
        case .text:
            return renderText(report, ui: CLIText(useColor: useColor))
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: DoctorReport, ui: CLIText) -> String {
        var sections: [[String]] = [[ui.section("Doctor")]]
        var checks: [String] = []
        var nextActions: [String] = []
        let hasProjectConfig = !report.checks.contains {
            $0.name == "project-config" && $0.message.contains("No \(ProjectConfigLoader.filename)")
        }

        for check in report.checks {
            if check.name == "next-actions" {
                nextActions = renderNextActions(check, ui: ui, hasProjectConfig: hasProjectConfig)
                continue
            }
            let line: String
            switch check.status {
            case .ok:
                line = ui.ok("\(check.name): \(check.message)")
            case .warn:
                line = ui.warn("\(check.name): \(check.message)")
            case .fail:
                line = ui.fail("\(check.name): \(check.message)")
            }
            checks.append(line)
        }

        if !checks.isEmpty {
            sections.append(checks)
        }
        if !nextActions.isEmpty {
            sections.append(nextActions)
        }
        return CLIText.joinSections(sections)
    }

    private func renderNextActions(_ check: DoctorCheck, ui: CLIText, hasProjectConfig: Bool) -> [String] {
        var lines = [ui.section("Next actions")]
        if check.status == .ok {
            lines.append(ui.ok(check.message))
            return lines
        }
        for line in check.message.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                lines.append(ui.palette.cyan("  \(text)"))
            } else {
                lines.append("  \(text)")
            }
        }
        if hasProjectConfig {
            lines.append(ui.hint("Tip: offsend sync   # materialize ignore files + hooks"))
        } else {
            lines.append(ui.hint("Tip: offsend init   # create .offsend.yml, then offsend sync"))
        }
        return lines
    }

    private func renderJSON(_ report: DoctorReport) -> String {
        struct Payload: Encodable {
            let isHealthy: Bool
            let checks: [CheckPayload]
            let suggestedActions: [String]
        }
        struct CheckPayload: Encodable {
            let name: String
            let status: String
            let message: String
        }

        let payload = Payload(
            isHealthy: report.isHealthy,
            checks: report.checks.map {
                CheckPayload(name: $0.name, status: $0.status.rawValue, message: $0.message)
            },
            suggestedActions: report.suggestedActions
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"isHealthy":false,"checks":[]}"#
        }
        return json
    }
}
