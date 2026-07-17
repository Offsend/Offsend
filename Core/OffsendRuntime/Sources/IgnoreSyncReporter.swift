import Foundation

public struct IgnoreSyncReporter: Sendable {
    public init() {}

    public func render(_ report: IgnoreSyncReport, format: CheckOutputFormat) -> String {
        switch format {
        case .text:
            return renderText(report)
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: IgnoreSyncReport) -> String {
        var lines: [String] = []
        for error in report.errors {
            lines.append("! \(error)")
        }

        if report.dryRun {
            if !report.createdRelativePaths.isEmpty {
                lines.append("Would create \(report.createdRelativePaths.count) ignore file(s):")
                for path in report.createdRelativePaths {
                    lines.append("  + \(path)")
                }
            }
            if !report.updatedRelativePaths.isEmpty {
                lines.append("Would update \(report.updatedRelativePaths.count) ignore file(s):")
                for path in report.updatedRelativePaths {
                    lines.append("  ~ \(path)")
                }
            }
            if report.excludeUpdated {
                if report.commitIgnoreFiles {
                    lines.append("Would remove local git exclude entries (\(report.excludePath ?? ".git/info/exclude"))")
                } else {
                    lines.append("Would update local git exclude (\(report.excludePath ?? ".git/info/exclude"))")
                }
            }
            if report.createdRelativePaths.isEmpty,
               report.updatedRelativePaths.isEmpty,
               !report.excludeUpdated,
               report.errors.isEmpty {
                lines.append("Nothing to sync; AI ignore files already match .offsend.yml")
            }
            return lines.joined(separator: "\n")
        }

        if !report.createdRelativePaths.isEmpty {
            lines.append("Created \(report.createdRelativePaths.count) ignore file(s):")
            for path in report.createdRelativePaths {
                lines.append("  + \(path)")
            }
        }
        if !report.updatedRelativePaths.isEmpty {
            lines.append("Updated \(report.updatedRelativePaths.count) ignore file(s):")
            for path in report.updatedRelativePaths {
                lines.append("  ~ \(path)")
            }
        }
        if report.excludeUpdated {
            if report.commitIgnoreFiles {
                lines.append("Removed local git exclude entries (ignore.commit: true)")
            } else {
                lines.append("Updated local git exclude (ignore files stay untracked)")
            }
        } else if !report.commitIgnoreFiles, report.excludePath != nil {
            lines.append("Ignore files kept local (ignore.commit: false)")
        }
        if report.createdRelativePaths.isEmpty,
           report.updatedRelativePaths.isEmpty,
           !report.excludeUpdated,
           report.errors.isEmpty {
            lines.append("Nothing to sync; AI ignore files already match .offsend.yml")
        }
        if !report.patterns.isEmpty {
            lines.append("Managed patterns: \(report.patterns.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private func renderJSON(_ report: IgnoreSyncReport) -> String {
        struct Payload: Encodable {
            let directory: String
            let dryRun: Bool
            let patterns: [String]
            let commitIgnoreFiles: Bool
            let createdRelativePaths: [String]
            let updatedRelativePaths: [String]
            let unchangedRelativePaths: [String]
            let excludeUpdated: Bool
            let excludePath: String?
            let errors: [String]
        }
        let payload = Payload(
            directory: report.directoryPath,
            dryRun: report.dryRun,
            patterns: report.patterns,
            commitIgnoreFiles: report.commitIgnoreFiles,
            createdRelativePaths: report.createdRelativePaths,
            updatedRelativePaths: report.updatedRelativePaths,
            unchangedRelativePaths: report.unchangedRelativePaths,
            excludeUpdated: report.excludeUpdated,
            excludePath: report.excludePath,
            errors: report.errors
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"errors":[]}"#
        }
        return json
    }
}
