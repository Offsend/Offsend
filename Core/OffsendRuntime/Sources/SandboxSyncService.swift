import Foundation

/// Materializes `sandbox` from `.offsend.yml` into each editor's own sandbox
/// configuration, the same way `ignore.patterns` is materialized into ignore
/// files.
///
/// Offsend generates and verifies; it does not enforce. Hooks run inside an
/// already-started agent, while a sandbox is applied when the process launches,
/// so for `nono` sync writes the profile and prints the launch hint.
/// `offsend run` executes that launch; `doctor` still reports it rather than
/// implying coverage for a process started outside Offsend.
public struct SandboxSyncService: Sendable {
    public struct FileChange: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable {
            case created
            case updated
            case unchanged
        }

        public let relativePath: String
        public let kind: Kind

        public init(relativePath: String, kind: Kind) {
            self.relativePath = relativePath
            self.kind = kind
        }
    }

    public struct Report: Equatable, Sendable {
        public let enabled: Bool
        public let plans: [SandboxTargetPlan]
        public let changes: [FileChange]
        /// `ignore.patterns` a path-based sandbox cannot express (basename globs).
        public let uncoveredPatterns: [String]
        /// Commands the user must run themselves, because Offsend cannot apply a
        /// process wrapper from inside a running agent.
        public let manualSteps: [String]
        public let errors: [String]

        public init(
            enabled: Bool,
            plans: [SandboxTargetPlan] = [],
            changes: [FileChange] = [],
            uncoveredPatterns: [String] = [],
            manualSteps: [String] = [],
            errors: [String] = []
        ) {
            self.enabled = enabled
            self.plans = plans
            self.changes = changes
            self.uncoveredPatterns = uncoveredPatterns
            self.manualSteps = manualSteps
            self.errors = errors
        }
    }

    public static let nonoProfileDirectory = ".offsend/nono"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func run(
        repositoryURL: URL,
        config: OffsendProjectConfig?,
        targets: [AIEditorHookTarget],
        nonoAvailable: Bool = SandboxMechanismResolver.nonoAvailable(),
        nonoConfigHome: URL? = nil,
        dryRun: Bool = false
    ) -> Report {
        guard config?.sandbox?.enabled == true else {
            return Report(enabled: false)
        }
        let root = repositoryURL.standardizedFileURL
        let sandbox = config?.sandbox
        let egress = OffsendSandboxNetworkDefault.effective(sandbox?.network?.default)
        let allowedDomains = (sandbox?.network?.allow ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        let coverage = SandboxPathCoverage.split(patterns: config?.ignore?.patterns ?? [])
        let plans = SandboxMechanismResolver.plan(targets: targets, nonoAvailable: nonoAvailable)
        let packProbe = NonoPackProbe(fileManager: fileManager, configHome: nonoConfigHome)

        var changes: [FileChange] = []
        var manualSteps: [String] = []
        var errors: [String] = []

        for plan in plans {
            do {
                switch plan.mechanism {
                case .cursorNative:
                    try changes.append(
                        writeCursorSandbox(
                            root: root,
                            egress: egress,
                            allowedDomains: allowedDomains,
                            dryRun: dryRun
                        )
                    )
                case .claudeNative:
                    try changes.append(
                        writeClaudeSandbox(
                            root: root,
                            egress: egress,
                            allowedDomains: allowedDomains,
                            denyRead: coverage.expressible,
                            ownsFilesystem: true,
                            dryRun: dryRun
                        )
                    )
                case .nono:
                    try changes.append(
                        writeNonoProfile(
                            root: root,
                            target: plan.target,
                            egress: egress,
                            allowedDomains: allowedDomains,
                            denyRead: coverage.expressible,
                            dryRun: dryRun
                        )
                    )
                    // One owner of filesystem isolation. Nested Seatbelt
                    // profiles conflict, so when nono wraps Claude, Claude's own
                    // sandbox is switched off on purpose rather than left to
                    // fight with it.
                    if plan.target == .claude {
                        try changes.append(
                            writeClaudeSandbox(
                                root: root,
                                egress: egress,
                                allowedDomains: allowedDomains,
                                denyRead: coverage.expressible,
                                ownsFilesystem: false,
                                dryRun: dryRun
                            )
                        )
                    }
                    if let pack = packProbe.probe(target: plan.target),
                       !pack.isSatisfied {
                        manualSteps.append(pack.missingMessage)
                    }
                    manualSteps.append(SandboxLaunch.nonoLaunchHint(for: plan.target))
                case .codexUserScope:
                    manualSteps.append(
                        "Codex sandboxing lives in ~/.codex/config.toml, outside this repository. "
                            + "Set sandbox_mode = \"workspace-write\" and the network policy there yourself; "
                            + "Offsend does not write user-scope files."
                    )
                case .unavailable:
                    break
                }
            } catch {
                errors.append("\(plan.target.rawValue): \(error.localizedDescription)")
            }
        }

        return Report(
            enabled: true,
            plans: plans,
            changes: changes,
            uncoveredPatterns: coverage.uncovered,
            manualSteps: manualSteps,
            errors: errors
        )
    }

    // MARK: - Cursor

    /// `.cursor/sandbox.json`. Cursor has no read-deny — `additionalReadonlyPaths`
    /// only widens reads, and `~/.ssh` stays readable no matter what — so only the
    /// network policy is written here.
    private func writeCursorSandbox(
        root: URL,
        egress: OffsendSandboxNetworkDefault,
        allowedDomains: [String],
        dryRun: Bool
    ) throws -> FileChange {
        let url = root.appendingPathComponent(".cursor/sandbox.json")
        var object = try loadJSONObject(at: url) ?? [:]
        // Never write `insecure_none`: that is the one value that turns the
        // sandbox off, and `check --policy` fails on it.
        if (object["type"] as? String) != "workspace_readonly" {
            object["type"] = "workspace_readwrite"
        }
        var network = object["networkPolicy"] as? [String: Any] ?? [:]
        network["default"] = egress.rawValue
        network["allow"] = allowedDomains
        object["networkPolicy"] = network
        return try write(object, to: url, root: root, dryRun: dryRun)
    }

    // MARK: - Claude

    /// `.claude/settings.json`. Claude's default read policy allows reading the
    /// whole machine — including `~/.aws` and `~/.ssh` — so `denyRead` is the
    /// part that actually buys something here.
    private func writeClaudeSandbox(
        root: URL,
        egress: OffsendSandboxNetworkDefault,
        allowedDomains: [String],
        denyRead: [String],
        ownsFilesystem: Bool,
        dryRun: Bool
    ) throws -> FileChange {
        let url = root.appendingPathComponent(".claude/settings.json")
        var object = try loadJSONObject(at: url) ?? [:]
        var sandbox = object["sandbox"] as? [String: Any] ?? [:]
        sandbox["enabled"] = ownsFilesystem
        if ownsFilesystem {
            // Without this, a command that fails under the sandbox is retried
            // outside it via `dangerouslyDisableSandbox`, and the guarantee
            // becomes theatre.
            sandbox["allowUnsandboxedCommands"] = false
            var network = sandbox["network"] as? [String: Any] ?? [:]
            switch egress {
            case .deny:
                network["allowedDomains"] = allowedDomains
            case .allow:
                network.removeValue(forKey: "allowedDomains")
            }
            sandbox["network"] = network
            var filesystem = sandbox["filesystem"] as? [String: Any] ?? [:]
            // `disabled: true` would keep network isolation but drop every read
            // protection, so it is removed rather than respected.
            filesystem.removeValue(forKey: "disabled")
            filesystem["denyRead"] = denyRead
            sandbox["filesystem"] = filesystem
        }
        object["sandbox"] = sandbox
        return try write(object, to: url, root: root, dryRun: dryRun)
    }

    // MARK: - nono

    /// A repo-local nono profile. `extends` keeps knowledge of toolchain paths
    /// inside nono's own security groups instead of copying it into Offsend,
    /// where it would rot.
    private func writeNonoProfile(
        root: URL,
        target: AIEditorHookTarget,
        egress: OffsendSandboxNetworkDefault,
        allowedDomains: [String],
        denyRead: [String],
        dryRun: Bool
    ) throws -> FileChange {
        let url = nonoProfileURL(root: root, target: target)
        var network: [String: Any] = [:]
        switch egress {
        case .deny:
            if allowedDomains.isEmpty {
                network["block"] = true
            } else {
                network["allow_domain"] = allowedDomains
            }
        case .allow:
            network["block"] = false
        }
        let object: [String: Any] = [
            "extends": nonoBaseProfile(for: target),
            "meta": [
                "name": nonoProfileName(for: target),
                "description": "Generated by offsend sync from .offsend.yml",
            ],
            "workdir": ["access": "readwrite"],
            // Deny rules narrow an already-allowed region; everything outside the
            // working directory is closed by the base profile's default-deny, so
            // only in-repo paths need naming here.
            "policy": ["add_deny_access": denyRead],
            "network": network,
        ]
        return try write(object, to: url, root: root, dryRun: dryRun)
    }

    public func nonoProfileURL(root: URL, target: AIEditorHookTarget) -> URL {
        root
            .appendingPathComponent(Self.nonoProfileDirectory)
            .appendingPathComponent("\(nonoProfileName(for: target)).json")
    }

    private func nonoProfileName(for target: AIEditorHookTarget) -> String {
        "offsend-\(target.rawValue)"
    }

    private func nonoBaseProfile(for target: AIEditorHookTarget) -> String {
        NonoPackRequirement.baseProfile(for: target)
    }

    // MARK: - Files

    private func write(
        _ object: [String: Any],
        to url: URL,
        root: URL,
        dryRun: Bool
    ) throws -> FileChange {
        let relativePath = relative(url, to: root)
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let existing = try? Data(contentsOf: url)
        if let existing, existing == data {
            return FileChange(relativePath: relativePath, kind: .unchanged)
        }
        let kind: FileChange.Kind = existing == nil ? .created : .updated
        guard !dryRun else {
            return FileChange(relativePath: relativePath, kind: kind)
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return FileChange(relativePath: relativePath, kind: kind)
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any]? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw SandboxSyncError.invalidExistingConfig(path: url.path)
        }
        return dictionary
    }

    private func relative(_ url: URL, to root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }
}

public enum SandboxSyncError: LocalizedError, Equatable {
    case invalidExistingConfig(path: String)

    public var errorDescription: String? {
        switch self {
        case .invalidExistingConfig(let path):
            return "\(path) is not a JSON object; fix or remove it, then re-run offsend sync."
        }
    }
}
