import DetectionCore
import Foundation

public struct CheckReporter: Sendable {
    public init() {}

    public func render(_ report: CheckReport, format: CheckOutputFormat, quiet: Bool) -> String {
        switch format {
        case .text:
            return renderText(report, quiet: quiet)
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: CheckReport, quiet: Bool) -> String {
        var lines: [String] = []

        for finding in report.fileFindings {
            let actionLabel = finding.recommendedAction.rawValue
            lines.append(
                "✗ \(finding.relativePath):\(finding.line)  \(displayName(for: finding.entityType))  [\(actionLabel)]"
            )
        }

        for finding in report.policyFindings where finding.status != .pass {
            let marker = finding.status == .fail ? "✗" : "!"
            lines.append("\(marker) policy  \(finding.message)  [\(finding.status.rawValue)]")
        }

        // File read/processing errors are always shown: a silently skipped file
        // could hide a secret, so --quiet must not suppress them.
        for issue in report.fileIssues {
            lines.append("! \(issue.relativePath)  \(issue.message)  [skipped]")
        }

        if lines.isEmpty {
            return quiet ? "" : "No sensitive data issues found."
        }

        if !quiet {
            let blocking = report.blockingCount
            let warnings = report.warningCount
            if report.shouldFail {
                lines.append("")
                if blocking > 0 {
                    lines.append("\(blocking) blocking issue(s) found. Check failed.")
                } else {
                    lines.append("\(warnings) warning issue(s) found. Check failed.")
                }
            } else if blocking > 0 || warnings > 0 {
                lines.append("")
                lines.append("\(blocking + warnings) issue(s) found (non-blocking).")
            }
        }

        return lines.joined(separator: "\n")
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
