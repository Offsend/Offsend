import Foundation
import WorkspacePolicyCore

public struct ShowReporter: Sendable {
    /// Cap per group so a directory full of one secret type can't flood the terminal;
    /// the full list stays available via `--format json`.
    private static let maxPathsPerGroup = 50

    public init() {}

    public func render(_ report: ShowReport, format: CheckOutputFormat, useColor: Bool = false) -> String {
        switch format {
        case .text:
            return renderText(report, palette: CLIPalette(enabled: useColor))
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: ShowReport, palette: CLIPalette) -> String {
        var lines: [String] = []

        for error in report.errors {
            lines.append("! \(error)")
        }

        if report.hasErrors, !report.hasExposure {
            return lines.joined(separator: "\n")
        }

        if !report.hasExposure {
            lines.append("AI boundary OK — no sensitive files are exposed to AI tools.")
            lines.append(contentsOf: renderMCPLines(report.mcp, palette: palette))
            lines.append(contentsOf: renderHistoryLines(report.history, palette: palette))
            lines.append(palette.dim("Next (optional): offsend hook install   # prompt/read/shell/MCP/subagent gates + git pre-commit"))
            lines.append(palette.dim("CI tip: offsend check --staged --policy --fail-on block"))
            return lines.joined(separator: "\n")
        }

        lines.append(palette.dim("Scanned: \(report.directoryPath)"))

        let fileWord = Self.pluralize(report.totalExposedCount, singular: "file")
        let summary = Self.severitySummary(for: report.groups)
        let suffix = summary.isEmpty ? "" : " (\(summary))"
        lines.append("\(report.totalExposedCount) \(fileWord) would be sent to AI tools\(suffix):")

        for group in report.groups {
            lines.append("")
            let header = "\(Self.marker(for: group.severity)) \(group.typeTitle) [\(group.severity)]"
            lines.append(Self.colorize(header, severity: group.severity, palette: palette))

            if !group.remediation.isEmpty {
                lines.append(palette.dim("    \(group.remediation)"))
            }

            for path in group.relativePaths.prefix(Self.maxPathsPerGroup) {
                lines.append("  - \(path)")
            }
            let overflow = group.relativePaths.count - Self.maxPathsPerGroup
            if overflow > 0 {
                lines.append(palette.dim("  … and \(overflow) more (use --format json for the full list)"))
            }
        }

        lines.append(contentsOf: renderMCPLines(report.mcp, palette: palette))
        lines.append(contentsOf: renderHistoryLines(report.history, palette: palette))
        return lines.joined(separator: "\n")
    }

    private func renderHistoryLines(_ history: ShowHistorySection, palette: CLIPalette) -> [String] {
        if history.skipped {
            return []
        }
        guard history.filesScanned > 0 || history.hasFindings else { return [] }
        var lines: [String] = ["", "Agent history"]
        lines.append("  \(history.filesScanned) local transcript file(s)")
        if history.hasFindings {
            lines.append("  \(history.filesWithFindings) with secret-shaped findings")
            if !history.secretTypes.isEmpty {
                lines.append(palette.dim("  types: \(history.secretTypes.joined(separator: ", "))"))
            }
            lines.append(palette.dim("  → offsend history scrub --apply"))
        } else if let message = history.message {
            lines.append(palette.dim("  → \(message)"))
        }
        return lines
    }

    private func renderMCPLines(_ mcp: ShowMCPSection, palette: CLIPalette) -> [String] {
        guard !mcp.isEmpty else { return [] }
        var lines: [String] = ["", "MCP"]
        let riskCount = mcp.servers.filter(\.highRisk).count
        var summary = "\(mcp.servers.count) server\(mcp.servers.count == 1 ? "" : "s")"
        if riskCount > 0 {
            summary += " (\(riskCount) high-risk)"
        }
        if let mode = mcp.policyMode, !mode.isEmpty {
            summary += "; policy: \(mode)"
        } else {
            summary += "; policy: unset"
        }
        if mcp.hasAllowlist || mcp.hasDenylist {
            var bits: [String] = []
            if mcp.hasAllowlist { bits.append("allowlist") }
            if mcp.hasDenylist { bits.append("denylist") }
            summary += " (\(bits.joined(separator: "+")))"
        }
        if mcp.gateTargets.isEmpty {
            summary += "; gate: missing"
        } else {
            summary += "; gate: \(mcp.gateTargets.joined(separator: ", "))"
        }
        lines.append("  \(summary)")
        for server in mcp.servers.prefix(20) {
            let risk = server.highRisk ? " !" : ""
            let detail = server.detail.isEmpty ? "" : " — \(server.detail)"
            lines.append("  - \(server.name) [\(server.source)]\(risk)\(detail)")
        }
        let overflow = mcp.servers.count - 20
        if overflow > 0 {
            lines.append(palette.dim("  … and \(overflow) more (use --format json for the full list)"))
        }
        if mcp.gateTargets.isEmpty {
            lines.append(palette.dim("  → offsend hook install   # add MCP gate (on by default)"))
        }
        if mcp.policyMode == nil {
            lines.append(palette.dim("  → set context.mcp in .offsend.yml to observe|ask|deny"))
        }
        return lines
    }

    private func renderJSON(_ report: ShowReport) -> String {
        struct GroupPayload: Encodable {
            let typeID: String
            let typeTitle: String
            let severity: String
            let remediation: String
            let relativePaths: [String]
        }
        struct MCPServerPayload: Encodable {
            let name: String
            let source: String
            let detail: String
            let highRisk: Bool
        }
        struct MCPPayload: Encodable {
            let servers: [MCPServerPayload]
            let policyMode: String?
            let hasAllowlist: Bool
            let hasDenylist: Bool
            let gateTargets: [String]
        }
        struct HistoryPayload: Encodable {
            let filesScanned: Int
            let filesWithFindings: Int
            let secretTypes: [String]
            let skipped: Bool
            let message: String?
        }
        struct Payload: Encodable {
            let directory: String
            let totalExposedCount: Int
            let scanIncomplete: Bool
            let groups: [GroupPayload]
            let errors: [String]
            let mcp: MCPPayload
            let history: HistoryPayload
        }

        let payload = Payload(
            directory: report.directoryPath,
            totalExposedCount: report.totalExposedCount,
            scanIncomplete: report.scanIncomplete,
            groups: report.groups.map {
                GroupPayload(
                    typeID: $0.typeID,
                    typeTitle: $0.typeTitle,
                    severity: $0.severity,
                    remediation: $0.remediation,
                    relativePaths: $0.relativePaths
                )
            },
            errors: report.errors,
            mcp: MCPPayload(
                servers: report.mcp.servers.map {
                    MCPServerPayload(
                        name: $0.name,
                        source: $0.source,
                        detail: $0.detail,
                        highRisk: $0.highRisk
                    )
                },
                policyMode: report.mcp.policyMode,
                hasAllowlist: report.mcp.hasAllowlist,
                hasDenylist: report.mcp.hasDenylist,
                gateTargets: report.mcp.gateTargets
            ),
            history: HistoryPayload(
                filesScanned: report.history.filesScanned,
                filesWithFindings: report.history.filesWithFindings,
                secretTypes: report.history.secretTypes,
                skipped: report.history.skipped,
                message: report.history.message
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"groups":[],"totalExposedCount":0,"errors":[]}"#
        }
        return json
    }

    private static func pluralize(_ count: Int, singular: String) -> String {
        count == 1 ? singular : "\(singular)s"
    }

    private static func marker(for severity: String) -> String {
        switch severity {
        case AIWorkspacePrivacyRuleSeverity.required.rawValue: return "✗"
        case AIWorkspacePrivacyRuleSeverity.recommended.rawValue: return "!"
        default: return "•"
        }
    }

    private static func colorize(_ text: String, severity: String, palette: CLIPalette) -> String {
        switch severity {
        case AIWorkspacePrivacyRuleSeverity.required.rawValue: return palette.red(text)
        case AIWorkspacePrivacyRuleSeverity.recommended.rawValue: return palette.yellow(text)
        default: return text
        }
    }

    /// "2 required, 1 recommended" — distinct exposed files per severity, most severe first.
    private static func severitySummary(for groups: [ShowExposedGroup]) -> String {
        var pathsBySeverity: [String: Set<String>] = [:]
        for group in groups {
            pathsBySeverity[group.severity, default: []].formUnion(group.relativePaths)
        }

        let order = [
            AIWorkspacePrivacyRuleSeverity.required.rawValue,
            AIWorkspacePrivacyRuleSeverity.recommended.rawValue,
            AIWorkspacePrivacyRuleSeverity.informational.rawValue
        ]
        return order.compactMap { severity in
            guard let count = pathsBySeverity[severity]?.count, count > 0 else { return nil }
            return "\(count) \(severity)"
        }
        .joined(separator: ", ")
    }
}
