import Foundation

public struct HookStatusReporter: Sendable {
    public init() {}

    public func render(_ report: HookStatusReport, format: CheckOutputFormat, useColor: Bool = false) -> String {
        switch format {
        case .text:
            return renderText(report, ui: CLIText(useColor: useColor))
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: HookStatusReport, ui: CLIText) -> String {
        let statusLine: String
        switch report.state {
        case .installed:
            statusLine = ui.ok("installed")
        case .notInstalled:
            statusLine = ui.warn("not installed")
        case .modified:
            statusLine = ui.fail("modified")
        }

        var lines = [
            ui.section("Hook status"),
            ui.note("repository: \(report.repositoryPath)"),
            "  hook: \(report.hookType.rawValue)",
            "  path: \(report.hookPath)",
            "  status: \(statusLine)",
        ]
        if let configPath = report.projectConfigPath {
            lines.append("  project-config: \(configPath)")
        }
        if let script = report.scriptPreview {
            lines.append("")
            lines.append(ui.note("preview:"))
            lines.append(script)
        }
        return CLIText.join(lines)
    }

    private func renderJSON(_ report: HookStatusReport) -> String {
        struct Payload: Encodable {
            let repositoryPath: String
            let hookType: String
            let hookPath: String
            let status: String
            let projectConfigPath: String?
            let scriptPreview: String?
        }

        let payload = Payload(
            repositoryPath: report.repositoryPath,
            hookType: report.hookType.rawValue,
            hookPath: report.hookPath,
            status: report.state.rawValue,
            projectConfigPath: report.projectConfigPath,
            scriptPreview: report.scriptPreview
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"status":"unknown"}"#
        }
        return json
    }
}
