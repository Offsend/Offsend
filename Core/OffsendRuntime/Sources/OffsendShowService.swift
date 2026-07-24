import Foundation
import WorkspacePolicyCore

/// Files of one sensitive-data type that are exposed to AI tools (not covered by
/// any effective ignore file).
public struct ShowExposedGroup: Sendable, Equatable {
    public let typeID: String
    public let typeTitle: String
    public let severity: String
    /// How to cover this data type, e.g. which ignore-file line to add.
    public let remediation: String
    public let relativePaths: [String]

    public init(typeID: String, typeTitle: String, severity: String, remediation: String, relativePaths: [String]) {
        self.typeID = typeID
        self.typeTitle = typeTitle
        self.severity = severity
        self.remediation = remediation
        self.relativePaths = relativePaths
    }
}

/// One MCP server discovered while auditing AI context exposure.
public struct ShowMCPServer: Sendable, Equatable {
    public let name: String
    public let source: String
    public let detail: String
    public let highRisk: Bool

    public init(name: String, source: String, detail: String, highRisk: Bool) {
        self.name = name
        self.source = source
        self.detail = detail
        self.highRisk = highRisk
    }
}

/// Local agent-transcript audit snapshot for `offsend show`.
public struct ShowHistorySection: Sendable, Equatable {
    public let filesScanned: Int
    public let filesWithFindings: Int
    public let secretTypes: [String]
    public let skipped: Bool
    /// True when transcript contents were scanned (`--scan-history` / `scan_in_show`),
    /// false for the default count-only section.
    public let contentScanned: Bool
    public let message: String?

    public init(
        filesScanned: Int = 0,
        filesWithFindings: Int = 0,
        secretTypes: [String] = [],
        skipped: Bool = false,
        contentScanned: Bool = false,
        message: String? = nil
    ) {
        self.filesScanned = filesScanned
        self.filesWithFindings = filesWithFindings
        self.secretTypes = secretTypes
        self.skipped = skipped
        self.contentScanned = contentScanned
        self.message = message
    }

    public var hasFindings: Bool { filesWithFindings > 0 }
}

/// One configured `context.mcp.rules` entry, summarized for show.
public struct ShowMCPRule: Sendable, Equatable {
    public let summary: String

    public init(summary: String) {
        self.summary = summary
    }
}

/// Recent MCP gate activity (from local `mcp-activity.log`).
public struct ShowMCPActivityHit: Sendable, Equatable {
    public let server: String
    public let tool: String
    public let kind: String
    public let count: Int
    public let lastCode: String
    public let secretTypes: [String]
    public let fieldsTransformed: Int

    public init(
        server: String,
        tool: String,
        kind: String,
        count: Int,
        lastCode: String,
        secretTypes: [String] = [],
        fieldsTransformed: Int = 0
    ) {
        self.server = server
        self.tool = tool
        self.kind = kind
        self.count = count
        self.lastCode = lastCode
        self.secretTypes = secretTypes
        self.fieldsTransformed = fieldsTransformed
    }

    public var label: String { "\(server)/\(tool)" }
}

/// MCP inventory + policy snapshot attached to `offsend show`.
public struct ShowMCPSection: Sendable, Equatable {
    public let servers: [ShowMCPServer]
    public let policyMode: String?
    public let responsesMode: String?
    public let hasAllowlist: Bool
    public let hasDenylist: Bool
    /// Editor targets that already have an Offsend MCP gate installed.
    public let gateTargets: [String]
    public let rules: [ShowMCPRule]
    public let recentActivity: [ShowMCPActivityHit]
    /// Soft guidance (high-risk without rules, activity without coverage).
    public let hints: [String]

    public init(
        servers: [ShowMCPServer] = [],
        policyMode: String? = nil,
        responsesMode: String? = nil,
        hasAllowlist: Bool = false,
        hasDenylist: Bool = false,
        gateTargets: [String] = [],
        rules: [ShowMCPRule] = [],
        recentActivity: [ShowMCPActivityHit] = [],
        hints: [String] = []
    ) {
        self.servers = servers
        self.policyMode = policyMode
        self.responsesMode = responsesMode
        self.hasAllowlist = hasAllowlist
        self.hasDenylist = hasDenylist
        self.gateTargets = gateTargets
        self.rules = rules
        self.recentActivity = recentActivity
        self.hints = hints
    }

    public var isEmpty: Bool {
        servers.isEmpty && rules.isEmpty && recentActivity.isEmpty
    }
}

/// What `offsend show` found: sensitive files exposed to AI tools (usable in further tool use),
/// grouped by data type.
public struct ShowReport: Sendable, Equatable {
    public let directoryPath: String
    /// Exposed sensitive files grouped by data type. Only non-empty groups are included.
    public let groups: [ShowExposedGroup]
    /// Count of unique exposed files across all groups.
    public let totalExposedCount: Int
    /// True when the workspace walk hit a file/time limit, so results may be incomplete.
    public let scanIncomplete: Bool
    public let errors: [String]
    /// Non-fatal issues (e.g. managed ignore drift); do not affect the exit code.
    public let warnings: [String]
    public let mcp: ShowMCPSection
    public let history: ShowHistorySection

    public init(
        directoryPath: String,
        groups: [ShowExposedGroup],
        totalExposedCount: Int,
        scanIncomplete: Bool,
        errors: [String],
        warnings: [String] = [],
        mcp: ShowMCPSection = ShowMCPSection(),
        history: ShowHistorySection = ShowHistorySection()
    ) {
        self.directoryPath = directoryPath
        self.groups = groups
        self.totalExposedCount = totalExposedCount
        self.scanIncomplete = scanIncomplete
        self.errors = errors
        self.warnings = warnings
        self.mcp = mcp
        self.history = history
    }

    public var hasErrors: Bool { !errors.isEmpty }
    public var hasExposure: Bool { totalExposedCount > 0 }
}

/// Lists sensitive files that are exposed to AI tools (`.cursorignore`, `.claudeignore`, …
/// do not cover them), mirroring the macOS app's directory exposure audit. Read-only:
/// only ignore-file contents are read, never the matched files themselves.
/// Opt-in `scanHistory` / `context.history.scan_in_show` also content-scans local agent transcripts.
public struct OffsendShowService: Sendable {
    private let configuration: AIWorkspacePrivacyAuditConfiguration
    private let auditor: AIWorkspacePrivacyAuditor
    private let runtimeContext: OffsendRuntimeContext?

    public init(
        context: OffsendRuntimeContext,
        auditor: AIWorkspacePrivacyAuditor = AIWorkspacePrivacyAuditor()
    ) {
        self.init(
            configuration: OffsendConfiguration.directoryCheckConfiguration(context: context),
            auditor: auditor,
            runtimeContext: context
        )
    }

    public init(
        configuration: AIWorkspacePrivacyAuditConfiguration,
        auditor: AIWorkspacePrivacyAuditor = AIWorkspacePrivacyAuditor(),
        runtimeContext: OffsendRuntimeContext? = nil
    ) {
        self.configuration = configuration
        self.auditor = auditor
        self.runtimeContext = runtimeContext
    }

    /// Count-only synchronous variant: never content-scans transcripts (ignores
    /// `scan_in_show`). Use `runAsync` for history content scanning.
    public func run(
        directoryURL: URL,
        homeDirectory: URL? = nil,
        projectConfig: OffsendProjectConfig? = nil
    ) -> ShowReport {
        let standardizedURL = directoryURL.standardizedFileURL
        let home = resolvedHome(homeDirectory)
        let config = projectConfig ?? (try? ProjectConfigLoader().load(from: standardizedURL))
        return buildReportSync(
            standardizedURL: standardizedURL,
            home: home,
            config: config
        )
    }

    public func runAsync(
        directoryURL: URL,
        homeDirectory: URL? = nil,
        projectConfig: OffsendProjectConfig? = nil,
        scanHistory: Bool = false
    ) async -> ShowReport {
        let standardizedURL = directoryURL.standardizedFileURL
        let home = resolvedHome(homeDirectory)
        let config = projectConfig ?? (try? ProjectConfigLoader().load(from: standardizedURL))
        let shouldScanHistory = scanHistory || (config?.context?.history?.scanInShow == true)
        return await buildReport(
            standardizedURL: standardizedURL,
            home: home,
            config: config,
            scanContent: shouldScanHistory
        )
    }

    private func resolvedHome(_ homeDirectory: URL?) -> URL {
        homeDirectory
            ?? ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private func buildReportSync(
        standardizedURL: URL,
        home: URL,
        config: OffsendProjectConfig?
    ) -> ShowReport {
        let mcpSection = Self.makeMCPSection(
            projectRoot: standardizedURL,
            homeDirectory: home,
            projectConfig: config
        )
        let historySection = Self.makeHistorySectionCountOnly(
            projectRoot: standardizedURL,
            homeDirectory: home,
            projectConfig: config
        )
        return finishReport(
            standardizedURL: standardizedURL,
            config: config,
            mcpSection: mcpSection,
            historySection: historySection
        )
    }

    private func buildReport(
        standardizedURL: URL,
        home: URL,
        config: OffsendProjectConfig?,
        scanContent: Bool
    ) async -> ShowReport {
        let mcpSection = Self.makeMCPSection(
            projectRoot: standardizedURL,
            homeDirectory: home,
            projectConfig: config
        )
        let historySection = await Self.makeHistorySection(
            projectRoot: standardizedURL,
            homeDirectory: home,
            projectConfig: config,
            runtimeContext: runtimeContext,
            scanContent: scanContent
        )
        return finishReport(
            standardizedURL: standardizedURL,
            config: config,
            mcpSection: mcpSection,
            historySection: historySection
        )
    }

    private func finishReport(
        standardizedURL: URL,
        config: OffsendProjectConfig?,
        mcpSection: ShowMCPSection,
        historySection: ShowHistorySection
    ) -> ShowReport {
        let audit = auditor.audit(directoryURL: standardizedURL, configuration: configuration)

        if audit.isDirectoryUnavailable {
            return ShowReport(
                directoryPath: standardizedURL.path,
                groups: [],
                totalExposedCount: 0,
                scanIncomplete: false,
                errors: audit.errors.map(\.message),
                mcp: mcpSection,
                history: historySection
            )
        }

        let groups = audit.sensitivePatternFindings
            .filter { !$0.exposedRelativePaths.isEmpty }
            .map { finding in
                ShowExposedGroup(
                    typeID: finding.pattern.id,
                    typeTitle: finding.pattern.title,
                    severity: finding.pattern.severity.rawValue,
                    remediation: finding.pattern.remediation,
                    relativePaths: finding.exposedRelativePaths.sorted()
                )
            }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return Self.severityRank(lhs.severity) < Self.severityRank(rhs.severity)
                }
                return lhs.typeTitle < rhs.typeTitle
            }

        var warnings: [String] = []
        if let patterns = config?.ignore?.patterns, !patterns.isEmpty {
            let drift = OffsendManagedIgnoreDrift.findings(
                directoryURL: standardizedURL,
                patterns: patterns,
                configuration: configuration
            )
            for item in drift {
                warnings.append(
                    "Managed ignore drift in \(item.relativePath): missing \(item.missingPatterns.joined(separator: ", ")). Shared policy in .offsend.yml is ahead of this file — run: offsend sync"
                )
            }
        }

        return ShowReport(
            directoryPath: standardizedURL.path,
            groups: groups,
            totalExposedCount: audit.allExposedRelativePaths.count,
            scanIncomplete: !audit.exposureScanCompletion.isComplete,
            errors: audit.errors.map(\.message),
            warnings: warnings,
            mcp: mcpSection,
            history: historySection
        )
    }

    private static func makeHistorySectionCountOnly(
        projectRoot: URL,
        homeDirectory: URL,
        projectConfig: OffsendProjectConfig?
    ) -> ShowHistorySection {
        if projectConfig?.context?.history?.audit == false {
            return ShowHistorySection(skipped: true, message: "context.history.audit is false")
        }
        let slug = OffsendHistoryService.cursorProjectSlug(for: projectRoot)
        let cursorDir = homeDirectory
            .appendingPathComponent(".cursor/projects")
            .appendingPathComponent(slug)
            .appendingPathComponent("agent-transcripts")
        let count = countTranscriptFiles(under: cursorDir)
            + countTranscriptFiles(under: projectRoot.appendingPathComponent(".cursor"))
        if count == 0 {
            return ShowHistorySection(filesScanned: 0, message: nil)
        }
        return ShowHistorySection(
            filesScanned: count,
            filesWithFindings: 0,
            secretTypes: [],
            message: "run offsend history audit to scan for secrets"
        )
    }

    private static func makeHistorySection(
        projectRoot: URL,
        homeDirectory: URL,
        projectConfig: OffsendProjectConfig?,
        runtimeContext: OffsendRuntimeContext?,
        scanContent: Bool
    ) async -> ShowHistorySection {
        if projectConfig?.context?.history?.audit == false {
            return ShowHistorySection(skipped: true, message: "context.history.audit is false")
        }

        if scanContent, let runtimeContext {
            let audit = await OffsendHistoryService().audit(
                projectRoot: projectRoot,
                homeDirectory: homeDirectory,
                context: runtimeContext,
                allProjects: false
            )
            let types = Array(Set(audit.findings.flatMap(\.secretTypes))).sorted()
            if audit.filesScanned == 0 {
                return ShowHistorySection(filesScanned: 0, contentScanned: true, message: nil)
            }
            if audit.hasFindings {
                return ShowHistorySection(
                    filesScanned: audit.filesScanned,
                    filesWithFindings: audit.filesWithFindings,
                    secretTypes: types,
                    contentScanned: true,
                    message: "run: offsend history scrub --apply"
                )
            }
            return ShowHistorySection(
                filesScanned: audit.filesScanned,
                filesWithFindings: 0,
                secretTypes: [],
                contentScanned: true,
                message: nil
            )
        }

        return makeHistorySectionCountOnly(
            projectRoot: projectRoot,
            homeDirectory: homeDirectory,
            projectConfig: projectConfig
        )
    }

    private static func countTranscriptFiles(under root: URL) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return 0 }
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            guard ext == "jsonl" || ext == "txt" else { continue }
            if url.path.contains("agent-transcripts") || root.path.contains("agent-transcripts") {
                count += 1
            }
            if count >= 500 { break }
        }
        return count
    }

    private static func makeMCPSection(
        projectRoot: URL,
        homeDirectory: URL,
        projectConfig: OffsendProjectConfig?
    ) -> ShowMCPSection {
        let inventory = OffsendMCPInventory().collect(
            projectRoot: projectRoot,
            homeDirectory: homeDirectory,
            mcpConfig: projectConfig?.context?.mcp
        )
        let installer = AIEditorHookInstaller()
        let gateTargets = AIEditorHookTarget.allCases
            .filter { AIEditorHookInstaller.supportsFileGates($0) }
            .filter { installer.status(target: $0, repositoryPath: projectRoot).mcpGate }
            .map(\.rawValue)
        let servers = inventory.servers.map {
            ShowMCPServer(
                name: $0.name,
                source: $0.source,
                detail: $0.detail,
                highRisk: $0.highRisk
            )
        }
        let mcpConfig = projectConfig?.context?.mcp
        let configuredRules = mcpConfig?.rules ?? []
        let ruleSummaries = configuredRules.map {
            ShowMCPRule(summary: OffsendMCPRuleAdvice.summarizeRule($0))
        }
        let activity = MCPActivityLog.recentFindingSummaries().map {
            ShowMCPActivityHit(
                server: $0.server,
                tool: $0.tool,
                kind: $0.kind,
                count: $0.count,
                lastCode: $0.lastCode,
                secretTypes: $0.secretTypes,
                fieldsTransformed: $0.fieldsTransformed
            )
        }
        var hints: [String] = []
        let uncovered = OffsendMCPRuleAdvice.uncoveredHighRiskServers(
            servers: servers,
            rules: configuredRules
        )
        if !uncovered.isEmpty {
            hints.append(
                "high-risk without rules: \(uncovered.joined(separator: ", ")) — add context.mcp.rules "
                    + "(see docs/configuration.md#contextmcp)"
            )
        }
        let uncoveredHits = OffsendMCPRuleAdvice.uncoveredActivityHits(
            hits: MCPActivityLog.recentFindingSummaries(),
            rules: configuredRules
        )
        if let hit = uncoveredHits.first {
            hints.append(
                "recent \(hit.label) had \(hit.lastCode) with no matching rule — consider "
                    + "context.mcp.rules match for that server/tool"
            )
        }
        if OffsendMCPRuleAdvice.hasFieldsWithoutSealResponses(
            rules: configuredRules,
            globalResponses: mcpConfig?.responses
        ) {
            hints.append(
                "fields rules only apply when that rule's effective responses is seal — "
                    + "set responses: seal on the rule or context.mcp.responses: seal "
                    + "(and offsend keygen --default)"
            )
        }

        return ShowMCPSection(
            servers: servers,
            policyMode: inventory.policyMode,
            responsesMode: mcpConfig?.responses,
            hasAllowlist: inventory.hasAllowlist,
            hasDenylist: inventory.hasDenylist,
            gateTargets: gateTargets,
            rules: ruleSummaries,
            recentActivity: activity,
            hints: hints
        )
    }

    /// Required exposure is the most dangerous, so it sorts first.
    private static func severityRank(_ severity: String) -> Int {
        switch severity {
        case AIWorkspacePrivacyRuleSeverity.required.rawValue: return 0
        case AIWorkspacePrivacyRuleSeverity.recommended.rawValue: return 1
        default: return 2
        }
    }
}
