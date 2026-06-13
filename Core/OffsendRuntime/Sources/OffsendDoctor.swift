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

            if context.isProEntitlementActive {
                checks.append(
                    DoctorCheck(
                        name: "license",
                        status: .ok,
                        message: "Pro entitlement is active."
                    )
                )
            } else {
                checks.append(
                    DoctorCheck(
                        name: "license",
                        status: .warn,
                        message: "Free tier limits apply (file size, custom dictionaries)."
                    )
                )
            }
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
        if let configURL = configLoader.configURL(for: cwd) {
            checks.append(
                DoctorCheck(
                    name: "project-config",
                    status: .ok,
                    message: configURL.path
                )
            )
        } else {
            checks.append(
                DoctorCheck(
                    name: "project-config",
                    status: .warn,
                    message: "No \(ProjectConfigLoader.filename) found for the current directory."
                )
            )
        }

        return DoctorReport(checks: checks)
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
