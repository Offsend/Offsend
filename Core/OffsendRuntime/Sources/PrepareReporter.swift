import Foundation

public struct PrepareReporter: Sendable {
    public init() {}

    public func render(_ report: PrepareReport, format: CheckOutputFormat, useColor: Bool = false) -> String {
        switch format {
        case .text:
            return renderText(report, ui: CLIText(useColor: useColor))
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: PrepareReport, ui: CLIText) -> String {
        var sections: [[String]] = []

        let errors = report.errors.map { ui.warn($0) }
        if !errors.isEmpty { sections.append(errors) }

        if report.dryRun {
            if report.plannedCreates.isEmpty && report.plannedUpdates.isEmpty {
                sections.append([ui.ok("Nothing to prepare; all AI ignore files are already present.")])
                return CLIText.joinSections(sections)
            }
            var body: [String] = [ui.section("Prepare (dry run)")]
            if !report.plannedCreates.isEmpty {
                body.append(ui.note("Would create \(report.plannedCreates.count) file(s):"))
                for file in report.plannedCreates {
                    body.append(ui.add(file.relativePath, detail: "(\(file.toolName))"))
                }
            }
            if !report.plannedUpdates.isEmpty {
                body.append(ui.note("Would update \(report.plannedUpdates.count) file(s):"))
                for update in report.plannedUpdates {
                    body.append(ui.update(update.relativePath, detail: "(+\(update.addedLines.joined(separator: ", ")))"))
                }
            }
            sections.append(body)
            return CLIText.joinSections(sections)
        }

        if report.createdRelativePaths.isEmpty, report.updatedRelativePaths.isEmpty, report.errors.isEmpty {
            sections.append([ui.ok("Nothing to prepare; all AI ignore files are already present.")])
            return CLIText.joinSections(sections)
        }

        var body: [String] = [ui.section("Prepare")]
        if !report.createdRelativePaths.isEmpty {
            body.append(ui.note("Created \(report.createdRelativePaths.count) file(s):"))
            for path in report.createdRelativePaths {
                body.append(ui.add(path))
            }
        }
        if !report.updatedRelativePaths.isEmpty {
            body.append(ui.note("Updated \(report.updatedRelativePaths.count) file(s):"))
            for path in report.updatedRelativePaths {
                body.append(ui.update(path))
            }
        }
        sections.append(body)
        return CLIText.joinSections(sections)
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
