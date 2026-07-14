import Foundation
import StorageCore

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

    public var isHealthy: Bool {
        !checks.contains { $0.status == .fail }
    }

    public init(checks: [DoctorCheck]) {
        self.checks = checks
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
                    if contents.contains(AIEditorHookInstaller.readWrapperRelativePath) {
                        let readURL = cwd.appendingPathComponent(AIEditorHookInstaller.readWrapperRelativePath)
                        let readIssue = installer.validateWrapper(at: readURL)
                        if readIssue != .ok {
                            details.append(
                                AIEditorHookInstaller.wrapperValidationMessage(readIssue, path: readURL.path)
                            )
                        }
                    }
                    if contents.contains(AIEditorHookInstaller.shellWrapperRelativePath) {
                        let shellURL = cwd.appendingPathComponent(AIEditorHookInstaller.shellWrapperRelativePath)
                        let shellIssue = installer.validateWrapper(at: shellURL)
                        if shellIssue != .ok {
                            details.append(
                                AIEditorHookInstaller.wrapperValidationMessage(shellIssue, path: shellURL.path)
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

        return DoctorReport(checks: checks)
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

    public func render(_ report: DoctorReport, format: CheckOutputFormat) -> String {
        switch format {
        case .text:
            return renderText(report)
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: DoctorReport) -> String {
        report.checks.map { check in
            let marker: String
            switch check.status {
            case .ok: marker = "✓"
            case .warn: marker = "!"
            case .fail: marker = "✗"
            }
            return "\(marker) \(check.name): \(check.message)"
        }
        .joined(separator: "\n")
    }

    private func renderJSON(_ report: DoctorReport) -> String {
        struct Payload: Encodable {
            let isHealthy: Bool
            let checks: [CheckPayload]
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
            }
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
