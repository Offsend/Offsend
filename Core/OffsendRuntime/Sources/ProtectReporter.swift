import Foundation

public struct ProtectReporter: Sendable {
    public init() {}

    public func render(_ report: ProtectReport, format: CheckOutputFormat) -> String {
        switch format {
        case .text:
            return renderText(report)
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: ProtectReport) -> String {
        var lines: [String] = []

        for error in report.errors {
            lines.append("! \(error)")
        }

        let prepareText = PrepareReporter().render(report.prepare, format: .text)
        if !prepareText.isEmpty {
            lines.append(prepareText)
        }

        if !report.addedToConfig.isEmpty {
            if !lines.isEmpty { lines.append("") }
            let verb = report.dryRun ? "Would add" : "Added"
            lines.append("\(verb) to \(ProjectConfigLoader.filename): \(report.addedToConfig.joined(separator: ", "))")
        }

        if report.patterns.isEmpty {
            if report.errors.isEmpty, report.sync == nil {
                lines.append("No required sensitive paths were exposed; nothing to add to AI ignore files.")
            }
        } else if let ignore = report.ignore {
            let ignoreText = IgnoreReporter().render(ignore, format: .text)
            if !ignoreText.isEmpty {
                if !lines.isEmpty { lines.append("") }
                lines.append("Patterns: \(report.patterns.joined(separator: ", "))")
                lines.append(ignoreText)
            }
        }

        if let sync = report.sync {
            let syncText = IgnoreSyncReporter().render(sync, format: .text)
            if !syncText.isEmpty {
                if !lines.isEmpty { lines.append("") }
                lines.append(syncText)
            }
        }

        if !lines.isEmpty { lines.append("") }

        if report.dryRun {
            lines.append(
                "Dry run — would leave \(report.remainingRequiredCount) required, \(report.remainingRecommendedCount) recommended exposed."
            )
            lines.append("Next: offsend protect   # apply, then offsend show to verify")
        } else if report.remainingRequiredCount == 0 {
            lines.append("AI boundary OK — no required sensitive paths exposed to AI tools.")
            if report.remainingRecommendedCount > 0 {
                lines.append(
                    "Still exposed (recommended): \(report.remainingRecommendedCount). Re-run with --include-recommended or offsend ignore <path>."
                )
            }
            lines.append("Next: offsend show   # verify, then offsend hook install")
        } else {
            lines.append(
                "Still exposed: \(report.remainingRequiredCount) required, \(report.remainingRecommendedCount) recommended."
            )
            lines.append("Next: offsend show   # inspect, or offsend ignore <path>")
        }

        if report.scanIncomplete {
            lines.append("! Scan incomplete — results may be partial.")
        }

        return lines.joined(separator: "\n")
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
