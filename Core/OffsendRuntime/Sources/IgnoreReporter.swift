import Foundation

public enum IgnoreCommandScope: String, Sendable {
    case local
    case project
}

public struct IgnoreReporter: Sendable {
    public init() {}

    public func render(
        _ report: IgnoreReport,
        format: CheckOutputFormat,
        scope: IgnoreCommandScope = .project
    ) -> String {
        switch format {
        case .text:
            return renderText(report, scope: scope)
        case .json:
            return renderJSON(report, scope: scope)
        }
    }

    private func renderText(_ report: IgnoreReport, scope: IgnoreCommandScope) -> String {
        var lines: [String] = []

        for error in report.errors {
            lines.append("! \(error)")
        }
        guard !report.patterns.isEmpty else {
            return lines.joined(separator: "\n")
        }

        if report.dryRun {
            if report.plannedCreates.isEmpty && report.plannedUpdates.isEmpty {
                lines.append("Nothing to do; every AI ignore file already covers: \(report.patterns.joined(separator: ", "))")
                appendLocalWarning(to: &lines, scope: scope)
                return lines.joined(separator: "\n")
            }
            if !report.plannedCreates.isEmpty {
                lines.append("Would create \(report.plannedCreates.count) file(s):")
                for path in report.plannedCreates {
                    lines.append("  + \(path)")
                }
            }
            if !report.plannedUpdates.isEmpty {
                lines.append("Would update \(report.plannedUpdates.count) file(s):")
                for update in report.plannedUpdates {
                    lines.append("  ~ \(update.relativePath)  (+\(update.addedLines.joined(separator: ", ")))")
                }
            }
            appendLocalWarning(to: &lines, scope: scope)
            return lines.joined(separator: "\n")
        }

        if !report.createdRelativePaths.isEmpty {
            lines.append("Created \(report.createdRelativePaths.count) file(s):")
            for path in report.createdRelativePaths {
                lines.append("  + \(path)")
            }
        }
        if !report.updatedRelativePaths.isEmpty {
            lines.append("Updated \(report.updatedRelativePaths.count) file(s):")
            for path in report.updatedRelativePaths {
                lines.append("  ~ \(path)")
            }
        }
        if report.createdRelativePaths.isEmpty, report.updatedRelativePaths.isEmpty, report.errors.isEmpty {
            lines.append("Nothing to do; every AI ignore file already covers: \(report.patterns.joined(separator: ", "))")
        }
        appendLocalWarning(to: &lines, scope: scope)

        return lines.joined(separator: "\n")
    }

    private func appendLocalWarning(to lines: inout [String], scope: IgnoreCommandScope) {
        guard scope == .local else { return }
        lines.append(
            "warning: Local only — not written to .offsend.yml and will not be shared with the team."
        )
        lines.append("To publish: offsend ignore <pattern>")
    }

    private func renderJSON(_ report: IgnoreReport, scope: IgnoreCommandScope) -> String {
        struct PlannedUpdatePayload: Encodable {
            let relativePath: String
            let addedLines: [String]
        }
        struct Payload: Encodable {
            let directory: String
            let dryRun: Bool
            let scope: String
            let published: Bool
            let patterns: [String]
            let plannedCreates: [String]
            let plannedUpdates: [PlannedUpdatePayload]
            let createdRelativePaths: [String]
            let updatedRelativePaths: [String]
            let unchangedRelativePaths: [String]
            let errors: [String]
        }

        let payload = Payload(
            directory: report.directoryPath,
            dryRun: report.dryRun,
            scope: scope.rawValue,
            published: scope == .project,
            patterns: report.patterns,
            plannedCreates: report.plannedCreates,
            plannedUpdates: report.plannedUpdates.map {
                PlannedUpdatePayload(relativePath: $0.relativePath, addedLines: $0.addedLines)
            },
            createdRelativePaths: report.createdRelativePaths,
            updatedRelativePaths: report.updatedRelativePaths,
            unchangedRelativePaths: report.unchangedRelativePaths,
            errors: report.errors
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"createdRelativePaths":[],"updatedRelativePaths":[],"errors":[]}"#
        }
        return json
    }
}
