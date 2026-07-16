import DetectionCore
import Foundation
import WorkspacePolicyCore

/// Baseline content scan run after `offsend init` (advise-only; does not fail init).
public enum OffsendInitBaseline {
    /// Collect regular files under `directory`, honoring `check.exclude` patterns.
    public static func collectFiles(
        in directory: URL,
        excludePatterns: [String],
        fileManager: FileManager = .default
    ) -> [URL] {
        let root = directory.standardizedFileURL
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                let relative = PathExcludeMatcher.relativePath(of: url, relativeTo: root)
                if PathExcludeMatcher.shouldSkipDirectory(relativePath: relative, patterns: excludePatterns) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values?.isRegularFile == true {
                files.append(url.standardizedFileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    public static func renderRemediation(report: CheckReport, maxFindings: Int = 40) -> String {
        var lines: [String] = []
        let findings = report.fileFindings
        if findings.isEmpty {
            lines.append("Baseline check: no sensitive data issues found.")
            return lines.joined(separator: "\n")
        }

        lines.append("Baseline check: \(findings.count) finding(s) in the working tree.")
        lines.append("Review each hit — real secrets should be removed/rotated; fixtures can be opted out.")
        lines.append("")

        for finding in findings.prefix(maxFindings) {
            let typeName = finding.entityType.rawValue
            lines.append("\(finding.relativePath):\(finding.line)  \(typeName)")
            if finding.hasCriticalSecret || finding.recommendedAction == .block {
                lines.append("  → Prefer: move to env / remove from the repo, and rotate if this was real")
                lines.append("  → Optional: offsend seal \(finding.relativePath)")
            } else {
                lines.append("  → Prefer: move to env if this is a real secret")
            }
            lines.append("  → If intentional (fixture/test): add at end of line  # offsend:ignore")
            lines.append("  → Or exclude the path in .offsend.yml under check.exclude")
        }

        let overflow = findings.count - maxFindings
        if overflow > 0 {
            lines.append("")
            lines.append("… and \(overflow) more (run: offsend check . --verbose)")
        }

        lines.append("")
        lines.append("Note: # offsend:ignore only affects `offsend check`, not AI prompt gates.")
        return lines.joined(separator: "\n")
    }
}
