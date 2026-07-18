import Foundation

public struct IgnoreSyncReporter: Sendable {
    public init() {}

    public func render(_ report: IgnoreSyncReport, format: CheckOutputFormat, useColor: Bool = false) -> String {
        switch format {
        case .text:
            return renderText(report, ui: CLIText(useColor: useColor))
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: IgnoreSyncReport, ui: CLIText) -> String {
        var sections: [[String]] = []

        let errors = report.errors.map { ui.warn($0) }
        if !errors.isEmpty { sections.append(errors) }

        let header = report.dryRun ? "Sync (dry run)" : "Sync"
        let gitignore = Self.relative(report.gitignorePath, root: report.directoryPath, fallback: ".gitignore")
        let exclude = Self.relative(report.excludePath, root: report.directoryPath, fallback: ".git/info/exclude")
        var body: [String] = []

        if report.dryRun {
            if !report.createdRelativePaths.isEmpty {
                body.append(ui.note("Would create \(report.createdRelativePaths.count) ignore file(s):"))
                for path in report.createdRelativePaths {
                    body.append(ui.add(path))
                }
            }
            if !report.updatedRelativePaths.isEmpty {
                body.append(ui.note("Would update \(report.updatedRelativePaths.count) ignore file(s):"))
                for path in report.updatedRelativePaths {
                    body.append(ui.update(path))
                }
            }
            if report.gitignoreUpdated {
                if report.commitIgnoreFiles {
                    body.append(ui.note("Would remove AI ignore entries from \(gitignore)"))
                } else {
                    body.append(ui.note("Would update \(gitignore) (keep AI ignore files untracked)"))
                }
            }
            if report.excludeUpdated {
                body.append(ui.note("Would remove stale local git exclude entries (\(exclude))"))
            }
            if body.isEmpty, report.errors.isEmpty {
                sections.append([ui.ok("Nothing to sync; AI ignore files already match .offsend.yml")])
                return CLIText.joinSections(sections)
            }
        } else {
            if !report.createdRelativePaths.isEmpty {
                body.append(ui.note("Created \(report.createdRelativePaths.count) ignore file(s):"))
                for path in report.createdRelativePaths {
                    body.append(ui.add(path))
                }
            }
            if !report.updatedRelativePaths.isEmpty {
                body.append(ui.note("Updated \(report.updatedRelativePaths.count) ignore file(s):"))
                for path in report.updatedRelativePaths {
                    body.append(ui.update(path))
                }
            }
            if report.gitignoreUpdated {
                if report.commitIgnoreFiles {
                    body.append(ui.note("Removed AI ignore entries from \(gitignore) (ignore.commit: true)"))
                } else {
                    body.append(ui.note("Updated \(gitignore) (AI ignore files stay untracked)"))
                }
            } else if !report.commitIgnoreFiles, report.gitignorePath != nil {
                body.append(ui.note("Ignore files kept local via \(gitignore) (ignore.commit: false)"))
            }
            if report.excludeUpdated {
                body.append(ui.note("Removed stale local git exclude entries"))
            }
            if body.isEmpty, report.errors.isEmpty {
                sections.append([ui.ok("Nothing to sync; AI ignore files already match .offsend.yml")])
                return CLIText.joinSections(sections)
            }
        }

        if !report.patterns.isEmpty {
            body.append(ui.note("Managed patterns: \(report.patterns.joined(separator: ", "))"))
        }

        if !body.isEmpty {
            sections.append([ui.section(header)] + body)
        }
        return CLIText.joinSections(sections)
    }

    /// Show paths relative to the scanned directory; absolute paths are noisy in terminal output.
    private static func relative(_ path: String?, root: String, fallback: String) -> String {
        guard let path, !path.isEmpty else { return fallback }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
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
            let gitignoreUpdated: Bool
            let gitignorePath: String?
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
            gitignoreUpdated: report.gitignoreUpdated,
            gitignorePath: report.gitignorePath,
            excludeUpdated: report.excludeUpdated,
            excludePath: report.excludePath,
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
