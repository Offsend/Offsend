import Foundation

public struct ProtectReporter: Sendable {
    public init() {}

    public func render(_ report: ProtectReport, format: CheckOutputFormat, useColor: Bool = false) -> String {
        switch format {
        case .text:
            return renderText(report, useColor: useColor)
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: ProtectReport, useColor: Bool) -> String {
        let ui = CLIText(useColor: useColor)
        var sections: [[String]] = []

        let errors = report.errors.map { ui.warn($0) }
        if !errors.isEmpty { sections.append(errors) }

        let prepareText = PrepareReporter().render(report.prepare, format: .text, useColor: useColor)
        if !prepareText.isEmpty {
            sections.append([prepareText])
        }

        if !report.addedToConfig.isEmpty {
            let verb = report.dryRun ? "Would add" : "Added"
            var configLines = [ui.section("Config")]
            configLines.append(ui.note("\(verb) to \(ProjectConfigLoader.filename):"))
            for pattern in report.addedToConfig {
                configLines.append(ui.add(pattern))
            }
            sections.append(configLines)
        }

        if report.patterns.isEmpty {
            if report.errors.isEmpty, report.sync == nil {
                sections.append([ui.ok("No required sensitive paths were exposed; nothing to add to AI ignore files.")])
            }
        } else if let ignore = report.ignore {
            let ignoreText = IgnoreReporter().render(ignore, format: .text, useColor: useColor)
            if !ignoreText.isEmpty {
                var patternLines = [ui.section("Patterns")]
                patternLines.append(ui.note(report.patterns.joined(separator: ", ")))
                sections.append(patternLines)
                sections.append([ignoreText])
            }
        }

        if let sync = report.sync {
            let syncText = IgnoreSyncReporter().render(sync, format: .text, useColor: useColor)
            if !syncText.isEmpty {
                sections.append([syncText])
            }
        }

        sections.append(statusLines(report, ui: ui))

        return CLIText.joinSections(sections)
    }

    /// One state-aware status block: markers describe the boundary, and there is
    /// exactly one `→ Next:` suggestion, chosen from the actual remaining state.
    private func statusLines(_ report: ProtectReport, ui: CLIText) -> [String] {
        var status: [String] = [ui.section("Status")]

        let boundaryClean = report.remainingRequiredCount == 0 && report.remainingRecommendedCount == 0
        let syncHasChanges = report.sync.map {
            !$0.createdRelativePaths.isEmpty || !$0.updatedRelativePaths.isEmpty
                || $0.gitignoreUpdated || $0.excludeUpdated
        } ?? false
        let wouldChangeAnything = !report.patterns.isEmpty || !report.addedToConfig.isEmpty || syncHasChanges

        if report.dryRun {
            if boundaryClean, !wouldChangeAnything {
                status.append(ui.ok("AI boundary OK — nothing to protect."))
                status.append(ui.next("offsend show   # verify, then offsend sync"))
            } else if boundaryClean {
                status.append(ui.ok("AI boundary OK — only ignore-file housekeeping pending."))
                status.append(ui.next("offsend protect   # apply housekeeping"))
            } else {
                status.append(
                    ui.note(
                        "Dry run — would leave \(report.remainingRequiredCount) required, \(report.remainingRecommendedCount) recommended exposed."
                    )
                )
                status.append(ui.next("offsend protect   # apply, then offsend show to verify"))
            }
        } else if report.remainingRequiredCount == 0 {
            status.append(ui.ok("AI boundary OK — no required sensitive paths exposed to AI tools."))
            if report.remainingRecommendedCount > 0 {
                status.append(
                    ui.warn(
                        "Still exposed (recommended): \(report.remainingRecommendedCount). Re-run with --include-recommended or offsend ignore <path>."
                    )
                )
            }
            status.append(ui.next("offsend show   # verify, then offsend sync"))
        } else {
            status.append(
                ui.warn(
                    "Still exposed: \(report.remainingRequiredCount) required, \(report.remainingRecommendedCount) recommended."
                )
            )
            status.append(ui.next("offsend show   # inspect, or offsend ignore <path>"))
        }

        if report.scanIncomplete {
            status.append(ui.warn("Scan incomplete — results may be partial."))
        }
        return status
    }

    private func renderJSON(_ report: ProtectReport) -> String {
        struct Payload: Encodable {
            let directory: String
            let dryRun: Bool
            let includeRecommended: Bool
            let patterns: [String]
            let addedToConfig: [String]
            let remainingRequiredCount: Int
            let remainingRecommendedCount: Int
            let scanIncomplete: Bool
            let prepareCreated: [String]
            let prepareUpdated: [String]
            let ignoreCreated: [String]
            let ignoreUpdated: [String]
            let syncCreated: [String]
            let syncUpdated: [String]
            let errors: [String]
        }

        let payload = Payload(
            directory: report.directoryPath,
            dryRun: report.dryRun,
            includeRecommended: report.includeRecommended,
            patterns: report.patterns,
            addedToConfig: report.addedToConfig,
            remainingRequiredCount: report.remainingRequiredCount,
            remainingRecommendedCount: report.remainingRecommendedCount,
            scanIncomplete: report.scanIncomplete,
            prepareCreated: report.prepare.dryRun
                ? report.prepare.plannedCreates.map(\.relativePath)
                : report.prepare.createdRelativePaths,
            prepareUpdated: report.prepare.dryRun
                ? report.prepare.plannedUpdates.map(\.relativePath)
                : report.prepare.updatedRelativePaths,
            ignoreCreated: report.ignore.map { $0.dryRun ? $0.plannedCreates : $0.createdRelativePaths } ?? [],
            ignoreUpdated: report.ignore.map { $0.dryRun ? $0.plannedUpdates.map(\.relativePath) : $0.updatedRelativePaths } ?? [],
            syncCreated: report.sync?.createdRelativePaths ?? [],
            syncUpdated: report.sync?.updatedRelativePaths ?? [],
            errors: report.errors
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"patterns":[],"errors":[]}"#
        }
        return json
    }
}
