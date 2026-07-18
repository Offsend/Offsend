import DetectionCore
import Foundation

public struct OffsendHistoryFinding: Equatable, Sendable {
    public let path: String
    public let source: String
    public let secretTypes: [String]
    public let findingCount: Int

    public init(path: String, source: String, secretTypes: [String], findingCount: Int) {
        self.path = path
        self.source = source
        self.secretTypes = secretTypes
        self.findingCount = findingCount
    }
}

public struct OffsendHistoryAuditReport: Equatable, Sendable {
    public let filesScanned: Int
    public let findings: [OffsendHistoryFinding]
    public let errors: [String]

    public init(filesScanned: Int, findings: [OffsendHistoryFinding], errors: [String] = []) {
        self.filesScanned = filesScanned
        self.findings = findings
        self.errors = errors
    }

    public var filesWithFindings: Int { findings.count }
    public var hasFindings: Bool { !findings.isEmpty }
}

public struct OffsendHistoryScrubReport: Equatable, Sendable {
    public let dryRun: Bool
    public let filesTouched: [String]
    public let redactionCount: Int
    public let findings: [OffsendHistoryFinding]
    public let errors: [String]

    public init(
        dryRun: Bool,
        filesTouched: [String],
        redactionCount: Int,
        findings: [OffsendHistoryFinding],
        errors: [String] = []
    ) {
        self.dryRun = dryRun
        self.filesTouched = filesTouched
        self.redactionCount = redactionCount
        self.findings = findings
        self.errors = errors
    }
}

/// Audits and redacts secret-shaped values in local AI agent transcripts (Cursor / Claude).
public struct OffsendHistoryService: Sendable {
    public static let maxFileBytes = 2 * 1024 * 1024
    public static let maxFilesDefault = 200

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func audit(
        projectRoot: URL,
        homeDirectory: URL,
        context: OffsendRuntimeContext,
        allProjects: Bool = false,
        disabledDetectors: Set<SensitiveEntityType> = [],
        customDictionaries: [CustomDictionaryItem] = [],
        maxFiles: Int = maxFilesDefault
    ) async -> OffsendHistoryAuditReport {
        let files = discoverTranscripts(
            projectRoot: projectRoot,
            homeDirectory: homeDirectory,
            allProjects: allProjects,
            maxFiles: maxFiles
        )
        var findings: [OffsendHistoryFinding] = []
        var errors: [String] = []
        let checker = OffsendCheckService(context: context)

        for file in files {
            do {
                guard let bounded = try loadBoundedText(at: file.url) else { continue }
                let result = await checker.runText(
                    bounded.text,
                    failPolicy: .block,
                    disabledDetectors: disabledDetectors,
                    customDictionaries: customDictionaries
                )
                let secrets = PromptCheckAdviceBuilder.filterEntities(result.entities, secretsOnly: true)
                guard !secrets.isEmpty else { continue }
                let types = Array(Set(secrets.map(\.type.rawValue))).sorted()
                findings.append(
                    OffsendHistoryFinding(
                        path: file.url.path,
                        source: file.source,
                        secretTypes: types,
                        findingCount: secrets.count
                    )
                )
            } catch {
                errors.append("\(file.url.path): \(error.localizedDescription)")
            }
        }

        return OffsendHistoryAuditReport(
            filesScanned: files.count,
            findings: findings.sorted { $0.path < $1.path },
            errors: errors
        )
    }

    public func scrub(
        projectRoot: URL,
        homeDirectory: URL,
        context: OffsendRuntimeContext,
        apply: Bool,
        allProjects: Bool = false,
        disabledDetectors: Set<SensitiveEntityType> = [],
        customDictionaries: [CustomDictionaryItem] = [],
        maxFiles: Int = maxFilesDefault
    ) async -> OffsendHistoryScrubReport {
        let files = discoverTranscripts(
            projectRoot: projectRoot,
            homeDirectory: homeDirectory,
            allProjects: allProjects,
            maxFiles: maxFiles
        )
        var findings: [OffsendHistoryFinding] = []
        var touched: [String] = []
        var redactionCount = 0
        var errors: [String] = []
        let checker = OffsendCheckService(context: context)

        for file in files {
            do {
                let modificationBefore = try modificationDate(of: file.url)
                guard let bounded = try loadBoundedText(at: file.url) else { continue }
                let result = await checker.runText(
                    bounded.text,
                    failPolicy: .block,
                    disabledDetectors: disabledDetectors,
                    customDictionaries: customDictionaries
                )
                let secrets = PromptCheckAdviceBuilder.filterEntities(result.entities, secretsOnly: true)
                guard !secrets.isEmpty else { continue }
                let types = Array(Set(secrets.map(\.type.rawValue))).sorted()
                findings.append(
                    OffsendHistoryFinding(
                        path: file.url.path,
                        source: file.source,
                        secretTypes: types,
                        findingCount: secrets.count
                    )
                )
                if bounded.truncated {
                    // Writing back a bounded prefix would drop the rest of the file.
                    errors.append(
                        "\(file.url.path): skipped scrub — file exceeds the \(Self.maxFileBytes / (1024 * 1024)) MB scan limit; redact manually"
                    )
                    continue
                }
                let (scrubbed, count) = Self.redact(text: bounded.text, entities: secrets)
                guard count > 0 else { continue }
                if apply {
                    let modificationNow = try modificationDate(of: file.url)
                    guard modificationBefore == modificationNow else {
                        errors.append(
                            "\(file.url.path): skipped scrub — file changed during scan (close active agent sessions and retry)"
                        )
                        continue
                    }
                    try scrubbed.write(to: file.url, atomically: true, encoding: .utf8)
                }
                redactionCount += count
                touched.append(file.url.path)
            } catch {
                errors.append("\(file.url.path): \(error.localizedDescription)")
            }
        }

        return OffsendHistoryScrubReport(
            dryRun: !apply,
            filesTouched: touched.sorted(),
            redactionCount: redactionCount,
            findings: findings.sorted { $0.path < $1.path },
            errors: errors
        )
    }

    /// Replace secret spans with `OFFSEND_REDACTED_<type>` (detector type only — no secret values).
    public static func redact(
        text: String,
        entities: [SensitiveEntity]
    ) -> (text: String, count: Int) {
        guard !entities.isEmpty else { return (text, 0) }
        var replacements: [(range: Range<String.Index>, placeholder: String)] = []
        var occupied: [Range<String.Index>] = []
        for entity in entities.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            guard entity.range.lowerBound >= text.startIndex,
                  entity.range.upperBound <= text.endIndex,
                  text[entity.range] == entity.value
            else { continue }
            if occupied.contains(where: { $0.overlaps(entity.range) }) { continue }
            occupied.append(entity.range)
            replacements.append((entity.range, "OFFSEND_REDACTED_\(entity.type.rawValue)"))
        }
        var output = text
        for replacement in replacements.reversed() {
            output.replaceSubrange(replacement.range, with: replacement.placeholder)
        }
        return (output, replacements.count)
    }

    public static func cursorProjectSlug(for projectRoot: URL) -> String {
        var path = projectRoot.standardizedFileURL.path
        if path.hasPrefix("/") {
            path.removeFirst()
        }
        return path
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    /// Claude Code project directory name: absolute path with non-alphanumerics replaced by `-`
    /// (e.g. `/Users/me/Projects/app` → `-Users-me-Projects-app`).
    public static func claudeProjectDirName(for projectRoot: URL) -> String {
        let path = projectRoot.standardizedFileURL.path
        return String(path.map { ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    // MARK: - Discovery

    private struct TranscriptFile {
        let url: URL
        let source: String
    }

    private func discoverTranscripts(
        projectRoot: URL,
        homeDirectory: URL,
        allProjects: Bool,
        maxFiles: Int
    ) -> [TranscriptFile] {
        var results: [TranscriptFile] = []
        let cursorProjects = homeDirectory.appendingPathComponent(".cursor/projects")
        if allProjects {
            results.append(contentsOf: collectUnder(
                cursorProjects,
                source: "cursor-transcript",
                remaining: maxFiles - results.count
            ))
        } else {
            let slug = Self.cursorProjectSlug(for: projectRoot)
            let projectTranscripts = cursorProjects
                .appendingPathComponent(slug)
                .appendingPathComponent("agent-transcripts")
            results.append(contentsOf: collectTranscriptFiles(
                under: projectTranscripts,
                source: "cursor-transcript",
                remaining: maxFiles - results.count
            ))
        }

        let claudeProjects = homeDirectory.appendingPathComponent(".claude/projects")
        if allProjects {
            results.append(contentsOf: collectUnder(
                claudeProjects,
                source: "claude-transcript",
                remaining: maxFiles - results.count
            ))
        } else {
            // Claude encodes the absolute project path as a directory name (non-alphanumerics → "-").
            // Match the exact encoded component so `app` never picks up `my-app` transcripts.
            let claudeDir = Self.claudeProjectDirName(for: projectRoot)
            results.append(contentsOf: collectUnder(
                claudeProjects,
                source: "claude-transcript",
                remaining: maxFiles - results.count,
                pathFilter: { $0.pathComponents.contains(claudeDir) }
            ))
        }

        // Project-local copies (rare, but ignore-template covers them).
        let localCursor = projectRoot.appendingPathComponent(".cursor")
        results.append(contentsOf: collectUnder(
            localCursor,
            source: "cursor-project-local",
            remaining: maxFiles - results.count
        ))

        var seen = Set<String>()
        return results.filter { seen.insert($0.url.path).inserted }.prefix(maxFiles).map { $0 }
    }

    private func collectUnder(
        _ root: URL,
        source: String,
        remaining: Int,
        pathFilter: ((URL) -> Bool)? = nil
    ) -> [TranscriptFile] {
        guard remaining > 0, fileManager.fileExists(atPath: root.path) else { return [] }
        return collectTranscriptFiles(under: root, source: source, remaining: remaining, pathFilter: pathFilter)
    }

    private func collectTranscriptFiles(
        under root: URL,
        source: String,
        remaining: Int,
        pathFilter: ((URL) -> Bool)? = nil
    ) -> [TranscriptFile] {
        guard remaining > 0 else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [TranscriptFile] = []
        while let url = enumerator.nextObject() as? URL {
            if files.count >= remaining { break }
            let ext = url.pathExtension.lowercased()
            guard ext == "jsonl" || ext == "txt" else { continue }
            // Prefer agent-transcripts trees; still accept Claude project jsonl.
            let path = url.path
            let looksLikeTranscript = path.contains("agent-transcripts")
                || path.contains("/.claude/projects/")
                || source == "claude-transcript"
            guard looksLikeTranscript else { continue }
            if let pathFilter, !pathFilter(url) { continue }
            var isFile: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isFile), !isFile.boolValue else {
                continue
            }
            files.append(TranscriptFile(url: url, source: source))
        }
        return files
    }

    private struct BoundedText {
        let text: String
        /// True when only a prefix of the file was read; the text must not be written back.
        let truncated: Bool
    }

    private func loadBoundedText(at url: URL) throws -> BoundedText? {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { return nil }
        if size > Self.maxFileBytes {
            // Read a bounded prefix rather than skipping entirely (scan only, never written back).
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var data = handle.readData(ofLength: Self.maxFileBytes)
            // The cut may land mid-way through a multi-byte UTF-8 sequence; drop trailing bytes until valid.
            var text = String(data: data, encoding: .utf8)
            var attempts = 0
            while text == nil, attempts < 3, !data.isEmpty {
                data.removeLast()
                attempts += 1
                text = String(data: data, encoding: .utf8)
            }
            guard let text else { return nil }
            return BoundedText(text: text, truncated: true)
        }
        return BoundedText(text: try String(contentsOf: url, encoding: .utf8), truncated: false)
    }

    private func modificationDate(of url: URL) throws -> Date? {
        try fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}

public enum OffsendHistoryReporter {
    public static func renderAudit(
        _ report: OffsendHistoryAuditReport,
        format: CheckOutputFormat,
        useColor: Bool = false
    ) -> String {
        switch format {
        case .text:
            return renderAuditText(report, ui: CLIText(useColor: useColor))
        case .json:
            return encodeJSON(AuditPayload(
                filesScanned: report.filesScanned,
                filesWithFindings: report.filesWithFindings,
                findings: report.findings.map {
                    FindingPayload(
                        path: $0.path,
                        source: $0.source,
                        secretTypes: $0.secretTypes,
                        findingCount: $0.findingCount
                    )
                },
                errors: report.errors
            ))
        }
    }

    public static func renderScrub(
        _ report: OffsendHistoryScrubReport,
        format: CheckOutputFormat,
        useColor: Bool = false
    ) -> String {
        switch format {
        case .text:
            return renderScrubText(report, ui: CLIText(useColor: useColor))
        case .json:
            return encodeJSON(ScrubPayload(
                dryRun: report.dryRun,
                filesTouched: report.filesTouched,
                redactionCount: report.redactionCount,
                findings: report.findings.map {
                    FindingPayload(
                        path: $0.path,
                        source: $0.source,
                        secretTypes: $0.secretTypes,
                        findingCount: $0.findingCount
                    )
                },
                errors: report.errors
            ))
        }
    }

    private static func renderAuditText(_ report: OffsendHistoryAuditReport, ui: CLIText) -> String {
        var lines: [String] = [ui.section("History audit")]
        for error in report.errors {
            lines.append(ui.warn(error))
        }
        lines.append(ui.note("Scanned \(report.filesScanned) agent transcript file(s)."))
        if report.findings.isEmpty {
            lines.append(ui.ok("No secret-shaped findings in local agent history."))
            return lines.joined(separator: "\n")
        }
        lines.append("\(report.filesWithFindings) file(s) with secret-shaped findings:")
        for finding in report.findings.prefix(50) {
            let types = finding.secretTypes.joined(separator: ", ")
            lines.append("  - \(finding.path) [\(finding.source)] (\(finding.findingCount): \(types))")
        }
        if report.findings.count > 50 {
            lines.append(ui.note("… and \(report.findings.count - 50) more (use --format json)"))
        }
        lines.append(ui.next("offsend history scrub --apply"))
        return lines.joined(separator: "\n")
    }

    private static func renderScrubText(_ report: OffsendHistoryScrubReport, ui: CLIText) -> String {
        var lines: [String] = [ui.section("History scrub")]
        for error in report.errors {
            lines.append(ui.warn(error))
        }
        let mode = report.dryRun ? "Dry-run" : "Applied"
        lines.append("\(mode): \(report.redactionCount) redaction(s) across \(report.filesTouched.count) file(s).")
        for path in report.filesTouched.prefix(50) {
            lines.append("  - \(path)")
        }
        if report.filesTouched.count > 50 {
            lines.append(ui.note("… and \(report.filesTouched.count - 50) more (use --format json)"))
        }
        if report.dryRun, report.redactionCount > 0 {
            lines.append(ui.next("offsend history scrub --apply"))
        }
        return lines.joined(separator: "\n")
    }

    private struct FindingPayload: Encodable {
        let path: String
        let source: String
        let secretTypes: [String]
        let findingCount: Int
    }

    private struct AuditPayload: Encodable {
        let filesScanned: Int
        let filesWithFindings: Int
        let findings: [FindingPayload]
        let errors: [String]
    }

    private struct ScrubPayload: Encodable {
        let dryRun: Bool
        let filesTouched: [String]
        let redactionCount: Int
        let findings: [FindingPayload]
        let errors: [String]
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
