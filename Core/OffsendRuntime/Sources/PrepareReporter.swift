import Foundation

public struct PrepareReporter: Sendable {
    public init() {}

    public func render(_ report: PrepareReport, format: CheckOutputFormat) -> String {
        switch format {
        case .text:
            return renderText(report)
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: PrepareReport) -> String {
        var lines: [String] = []

        for error in report.errors {
            lines.append("! \(error)")
        }

        if report.dryRun {
            if report.plannedCreates.isEmpty && report.plannedUpdates.isEmpty {
                lines.append("Nothing to prepare; all AI ignore files are already present.")
                return lines.joined(separator: "\n")
            }
            if !report.plannedCreates.isEmpty {
                lines.append("Would create \(report.plannedCreates.count) file(s):")
                for file in report.plannedCreates {
                    lines.append("  + \(file.relativePath)  (\(file.toolName))")
                }
            }
            if !report.plannedUpdates.isEmpty {
                lines.append("Would update \(report.plannedUpdates.count) file(s):")
                for update in report.plannedUpdates {
                    lines.append("  ~ \(update.relativePath)  (+\(update.addedLines.joined(separator: ", ")))")
                }
            }
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
            lines.append("Nothing to prepare; all AI ignore files are already present.")
        }

        return lines.joined(separator: "\n")
    }

    private func renderJSON(_ report: PrepareReport) -> String {
        struct PlannedFilePayload: Encodable {
            let relativePath: String
            let toolName: String
            let required: Bool
        }
        struct PlannedUpdatePayload: Encodable {
            let relativePath: String
            let addedLines: [String]
        }
        struct Payload: Encodable {
            let directory: String
            let dryRun: Bool
            let plannedCreates: [PlannedFilePayload]
            let plannedUpdates: [PlannedUpdatePayload]
            let createdRelativePaths: [String]
            let updatedRelativePaths: [String]
            let errors: [String]
        }

        let payload = Payload(
            directory: report.directoryPath,
            dryRun: report.dryRun,
            plannedCreates: report.plannedCreates.map {
                PlannedFilePayload(relativePath: $0.relativePath, toolName: $0.toolName, required: $0.required)
            },
            plannedUpdates: report.plannedUpdates.map {
                PlannedUpdatePayload(relativePath: $0.relativePath, addedLines: $0.addedLines)
            },
            createdRelativePaths: report.createdRelativePaths,
            updatedRelativePaths: report.updatedRelativePaths,
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
