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
        gitExecutable: String = "/usr/bin/git"
    ) {
        self.fileManager = fileManager
        self.gitExecutable = gitExecutable
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
                    message: "Could not load Offsend settings from Application Support."
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
                    message: "offsend executable not found in PATH or Offsend.app Contents/Helpers."
                )
            )
        }

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
