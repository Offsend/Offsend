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
        scope: IgnoreCommandScope = .project,
        useColor: Bool = false
    ) -> String {
        switch format {
        case .text:
            return renderText(report, scope: scope, ui: CLIText(useColor: useColor))
        case .json:
            return renderJSON(report, scope: scope)
        }
    }

    private func renderText(_ report: IgnoreReport, scope: IgnoreCommandScope, ui: CLIText) -> String {
        var sections: [[String]] = []

        let errors = report.errors.map { ui.warn($0) }
        if !errors.isEmpty { sections.append(errors) }

        guard !report.patterns.isEmpty else {
            return CLIText.joinSections(sections)
        }

        let header = report.dryRun ? "Ignore (dry run)" : "Ignore"
        var body: [String] = [ui.section(header)]

        if report.dryRun {
            if report.plannedCreates.isEmpty && report.plannedUpdates.isEmpty {
                body = [ui.ok("Nothing to do; every AI ignore file already covers: \(report.patterns.joined(separator: ", "))")]
                appendLocalWarning(to: &body, scope: scope, ui: ui)
                sections.append(body)
                return CLIText.joinSections(sections)
            }
            if !report.plannedCreates.isEmpty {
                body.append(ui.note("Would create \(report.plannedCreates.count) file(s):"))
                for path in report.plannedCreates {
                    body.append(ui.add(path))
                }
            }
            if !report.plannedUpdates.isEmpty {
                body.append(ui.note("Would update \(report.plannedUpdates.count) file(s):"))
                for update in report.plannedUpdates {
                    body.append(ui.update(update.relativePath, detail: "(+\(update.addedLines.joined(separator: ", ")))"))
                }
            }
            appendLocalWarning(to: &body, scope: scope, ui: ui)
            sections.append(body)
            return CLIText.joinSections(sections)
        }

        if report.createdRelativePaths.isEmpty, report.updatedRelativePaths.isEmpty, report.errors.isEmpty {
            body = [ui.ok("Nothing to do; every AI ignore file already covers: \(report.patterns.joined(separator: ", "))")]
            appendLocalWarning(to: &body, scope: scope, ui: ui)
            sections.append(body)
            return CLIText.joinSections(sections)
        }

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
        appendLocalWarning(to: &body, scope: scope, ui: ui)
        sections.append(body)
        return CLIText.joinSections(sections)
    }

    private func appendLocalWarning(to lines: inout [String], scope: IgnoreCommandScope, ui: CLIText) {
        guard scope == .local else { return }
        lines.append(ui.warn("Local only — not written to .offsend.yml and will not be shared with the team."))
        lines.append(ui.next("offsend ignore <pattern>"))
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
