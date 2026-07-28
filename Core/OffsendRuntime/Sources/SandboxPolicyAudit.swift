import Foundation

/// Verifies that the sandbox a project declared is the sandbox still configured.
///
/// Generation alone is not a guarantee: every native config stays editable by
/// hand and by the agent, and each mechanism ships exactly one key that keeps the
/// sandbox nominally on while removing what it was for. Those keys are checked by
/// name here, and `check --policy` fails on them.
public enum SandboxPolicyAudit {
    public struct Finding: Equatable, Sendable {
        public let message: String
        /// Weakening and drift fail; an unenforceable declaration only warns,
        /// because no local edit caused it.
        public let isFailure: Bool

        public init(message: String, isFailure: Bool) {
            self.message = message
            self.isFailure = isFailure
        }
    }

    public static func findings(
        repositoryURL: URL,
        config: OffsendProjectConfig?,
        targets: [AIEditorHookTarget]? = nil,
        nonoAvailable: Bool = SandboxMechanismResolver.nonoAvailable(),
        homeDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [Finding] {
        // No declaration, no claim to verify. Weakened native configs are the
        // project's own business until `.offsend.yml` says otherwise.
        guard config?.sandbox?.enabled == true else { return [] }

        let root = repositoryURL.standardizedFileURL
        let home = homeDirectory
            ?? ProcessInfo.processInfo.environment["HOME"].flatMap {
                $0.isEmpty ? nil : URL(fileURLWithPath: $0)
            }
            ?? fileManager.homeDirectoryForCurrentUser
        let targets = targets ?? AIEditorHookTarget.detectedTargets(
            repositoryPath: root,
            homeDirectory: home,
            fileManager: fileManager
        )
        var findings: [Finding] = []
        let plans = SandboxMechanismResolver.plan(targets: targets, nonoAvailable: nonoAvailable)

        let drift = SandboxSyncService(fileManager: fileManager).run(
            repositoryURL: root,
            config: config,
            targets: targets,
            nonoAvailable: nonoAvailable,
            dryRun: true
        )
        for change in drift.changes where change.kind != .unchanged {
            findings.append(Finding(
                message: "Sandbox config drift in \(change.relativePath): "
                    + "policy in .offsend.yml is ahead of this file. Run: offsend sync",
                isFailure: true
            ))
        }

        for plan in plans {
            switch plan.mechanism {
            case .cursorNative:
                findings.append(contentsOf: cursorFindings(root: root, fileManager: fileManager))
            case .claudeNative:
                findings.append(
                    contentsOf: claudeFindings(root: root, ownsFilesystem: true, fileManager: fileManager)
                )
            case .nono:
                if plan.target == .claude {
                    findings.append(
                        contentsOf: claudeFindings(root: root, ownsFilesystem: false, fileManager: fileManager)
                    )
                }
            case .codexUserScope:
                findings.append(contentsOf: codexFindings(home: home, fileManager: fileManager))
            case .unavailable:
                findings.append(Finding(
                    message: "\(plan.target.rawValue) has no sandbox, so sandbox.enabled cannot be honored there. "
                        + "Nothing is enforced for that editor.",
                    isFailure: false
                ))
            }
        }
        return findings
    }

    private static func cursorFindings(root: URL, fileManager: FileManager) -> [Finding] {
        let path = ".cursor/sandbox.json"
        guard let object = loadJSON(root.appendingPathComponent(path), fileManager: fileManager) else {
            return []
        }
        guard (object["type"] as? String) == "insecure_none" else { return [] }
        return [Finding(
            message: "\(path): type is insecure_none, which disables the sandbox entirely "
                + "while .offsend.yml requires one.",
            isFailure: true
        )]
    }

    private static func claudeFindings(
        root: URL,
        ownsFilesystem: Bool,
        fileManager: FileManager
    ) -> [Finding] {
        let path = ".claude/settings.json"
        guard let object = loadJSON(root.appendingPathComponent(path), fileManager: fileManager),
              let sandbox = object["sandbox"] as? [String: Any] else {
            return []
        }
        // When nono owns filesystem isolation, Claude's own sandbox is off by
        // design; the weakening keys below say nothing in that case.
        guard ownsFilesystem else { return [] }

        var findings: [Finding] = []
        if sandbox["enabled"] as? Bool != true {
            findings.append(Finding(
                message: "\(path): sandbox.enabled is not true while .offsend.yml requires a sandbox.",
                isFailure: true
            ))
        }
        if sandbox["allowUnsandboxedCommands"] as? Bool == true {
            findings.append(Finding(
                message: "\(path): allowUnsandboxedCommands is true, so any command that fails inside "
                    + "the sandbox can be retried outside it. The sandbox then guarantees nothing.",
                isFailure: true
            ))
        }
        if let filesystem = sandbox["filesystem"] as? [String: Any],
           filesystem["disabled"] as? Bool == true {
            findings.append(Finding(
                message: "\(path): filesystem.disabled is true, which drops every read restriction "
                    + "while leaving the sandbox nominally enabled.",
                isFailure: true
            ))
        }
        return findings
    }

    /// Codex keeps sandbox settings in `~/.codex/config.toml`, which `offsend
    /// sync` deliberately does not write. It can still be read, so the one value
    /// that turns everything off is reported rather than ignored.
    private static func codexFindings(home: URL, fileManager: FileManager) -> [Finding] {
        let url = home.appendingPathComponent(".codex/config.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [Finding(
                message: "Codex sandboxing is configured in ~/.codex/config.toml, outside this repository. "
                    + "Offsend cannot verify it; set sandbox_mode there yourself.",
                isFailure: false
            )]
        }
        guard text.range(
            of: #"(?m)^\s*sandbox_mode\s*=\s*['"]danger-full-access['"]"#,
            options: .regularExpression
        ) != nil else {
            return []
        }
        return [Finding(
            message: "~/.codex/config.toml: sandbox_mode = \"danger-full-access\" removes the sandbox "
                + "while .offsend.yml requires one.",
            isFailure: true
        )]
    }

    private static func loadJSON(_ url: URL, fileManager: FileManager) -> [String: Any]? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return object as? [String: Any]
    }
}
