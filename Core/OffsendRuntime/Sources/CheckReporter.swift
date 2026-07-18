import DetectionCore
import Foundation

public struct CheckReporter: Sendable {
    public init() {}

    /// Cap on files listed in the digest; the rest collapse into a "… and N more" line.
    /// `--verbose` bypasses this and lists every finding individually.
    private static let maxDigestFiles = 10

    public func render(
        _ report: CheckReport,
        format: CheckOutputFormat,
        quiet: Bool,
        verbose: Bool = false,
        useColor: Bool = false
    ) -> String {
        switch format {
        case .text:
            return renderText(report, quiet: quiet, verbose: verbose, palette: CLIPalette(enabled: useColor))
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: CheckReport, quiet: Bool, verbose: Bool, palette: CLIPalette) -> String {
        var lines: [String] = []

        if verbose {
            lines.append(contentsOf: verboseFindingLines(report, palette: palette))
        } else {
            lines.append(contentsOf: digestFindingLines(report, palette: palette))
        }

        for finding in report.policyFindings where finding.status != .pass {
            let marker = finding.status == .fail ? "✗" : "!"
            let line = "\(marker) policy  \(finding.message)  [\(finding.status.rawValue)]"
            lines.append(finding.status == .fail ? palette.red(line) : palette.yellow(line))
        }

        // Skipped files are always surfaced (a silently skipped file could hide a secret),
        // but collapsed to a count unless --verbose asks for the full list.
        if !report.fileIssues.isEmpty {
            if verbose {
                for issue in report.fileIssues {
                    lines.append(palette.yellow("! \(issue.relativePath)  \(issue.message)  [skipped]"))
                }
            } else {
                let count = report.fileIssues.count
                lines.append(palette.dim("! \(count) \(Self.pluralize(count, "file")) skipped (use --verbose to list)"))
            }
        }

        if lines.isEmpty {
            return quiet ? "" : palette.green("✓ No sensitive data issues found.")
        }

        if !quiet, let summary = summaryLine(report, palette: palette) {
            lines.append("")
            lines.append(summary)
        }

        return lines.joined(separator: "\n")
    }

    private func verboseFindingLines(_ report: CheckReport, palette: CLIPalette) -> [String] {
        report.fileFindings.map { finding in
            let line = "✗ \(finding.relativePath):\(finding.line)  \(displayName(for: finding.entityType))  [\(finding.recommendedAction.rawValue)]"
            return Self.isBlocking(finding) ? palette.red(line) : palette.yellow(line)
        }
    }

    /// One line per affected file: `<marker> <path>  N blocking, M warning(s)`,
    /// most severe and noisiest files first, capped by `maxDigestFiles`.
    private func digestFindingLines(_ report: CheckReport, palette: CLIPalette) -> [String] {
        guard !report.fileFindings.isEmpty else { return [] }

        var countsByFile: [String: (blocking: Int, warning: Int)] = [:]
        var order: [String] = []
        for finding in report.fileFindings {
            if countsByFile[finding.relativePath] == nil { order.append(finding.relativePath) }
            if Self.isBlocking(finding) {
                countsByFile[finding.relativePath, default: (0, 0)].blocking += 1
            } else {
                countsByFile[finding.relativePath, default: (0, 0)].warning += 1
            }
        }

        let sorted = order.sorted { lhs, rhs in
            let left = countsByFile[lhs]!
            let right = countsByFile[rhs]!
            if (left.blocking > 0) != (right.blocking > 0) { return left.blocking > 0 }
            let leftTotal = left.blocking + left.warning
            let rightTotal = right.blocking + right.warning
            if leftTotal != rightTotal { return leftTotal > rightTotal }
            return lhs < rhs
        }

        let shown = Array(sorted.prefix(Self.maxDigestFiles))
        let pad = shown.map(\.count).max() ?? 0
        var lines: [String] = shown.map { path in
            let counts = countsByFile[path]!
            let paddedPath = path.padding(toLength: pad, withPad: " ", startingAt: 0)
            let line = "\(counts.blocking > 0 ? "✗" : "!") \(paddedPath)  \(Self.countsText(counts))"
            return counts.blocking > 0 ? palette.red(line) : palette.yellow(line)
        }

        let overflow = sorted.count - shown.count
        if overflow > 0 {
            lines.append(palette.dim("  … and \(overflow) more \(Self.pluralize(overflow, "file")) (use --verbose)"))
        }
        return lines
    }

    private func summaryLine(_ report: CheckReport, palette: CLIPalette) -> String? {
        let blocking = report.blockingCount
        let warnings = report.warningCount
        let fileCount = Set(report.fileFindings.map(\.relativePath)).count
        let scope = fileCount > 0 ? " across \(fileCount) \(Self.pluralize(fileCount, "file"))" : ""

        if report.shouldFail {
            if blocking > 0 {
                return palette.red("\(blocking) blocking, \(warnings) warning(s)\(scope). Check failed.")
            }
            return palette.yellow("\(warnings) warning(s)\(scope). Check failed.")
        }

        if blocking > 0 || warnings > 0 {
            return palette.dim("\(blocking + warnings) issue(s)\(scope) (non-blocking).")
        }
        return nil
    }

    private static func isBlocking(_ finding: FileCheckFinding) -> Bool {
        finding.recommendedAction == .block || finding.hasCriticalSecret
    }

    private static func countsText(_ counts: (blocking: Int, warning: Int)) -> String {
        var parts: [String] = []
        if counts.blocking > 0 { parts.append("\(counts.blocking) blocking") }
        if counts.warning > 0 { parts.append("\(counts.warning) \(pluralize(counts.warning, "warning"))") }
        return parts.joined(separator: ", ")
    }

    private static func pluralize(_ count: Int, _ singular: String) -> String {
        count == 1 ? singular : "\(singular)s"
    }

    private func renderJSON(_ report: CheckReport) -> String {
        let payload = JSONReportPayload(report: report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"shouldFail":false,"fileFindings":[],"fileIssues":[],"policyFindings":[]}"#
        }
        return json
    }

    private func displayName(for type: SensitiveEntityType) -> String {
        type.placeholderPrefix.replacingOccurrences(of: "_", with: " ").lowercased()
    }
}

private struct JSONReportPayload: Encodable {
    let shouldFail: Bool
    let blockingCount: Int
    let warningCount: Int
    let fileFindings: [JSONFileFinding]
    let fileIssues: [JSONFileIssue]
    let policyFindings: [JSONPolicyFinding]

    init(report: CheckReport) {
        shouldFail = report.shouldFail
        blockingCount = report.blockingCount
        warningCount = report.warningCount
        fileFindings = report.fileFindings.map(JSONFileFinding.init)
        fileIssues = report.fileIssues.map(JSONFileIssue.init)
        policyFindings = report.policyFindings.map(JSONPolicyFinding.init)
    }
}

private struct JSONFileFinding: Encodable {
    let relativePath: String
    let line: Int
    let entityType: String
    let recommendedAction: String
    let hasCriticalSecret: Bool

    init(_ finding: FileCheckFinding) {
        relativePath = finding.relativePath
        line = finding.line
        entityType = finding.entityType.rawValue
        recommendedAction = finding.recommendedAction.rawValue
        hasCriticalSecret = finding.hasCriticalSecret
    }
}

private struct JSONFileIssue: Encodable {
    let relativePath: String
    let message: String

    init(_ issue: FileCheckIssue) {
        relativePath = issue.relativePath
        message = issue.message
    }
}

private struct JSONPolicyFinding: Encodable {
    let message: String
    let status: String

    init(_ finding: PolicyCheckFinding) {
        message = finding.message
        status = finding.status.rawValue
    }
}
