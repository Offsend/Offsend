import Foundation

/// The mechanism that will actually enforce `sandbox.enabled` for one editor.
///
/// Chosen by Offsend rather than named in `.offsend.yml`, so replacing the tool
/// later is not a config migration. `offsend doctor` always prints the choice:
/// automatic is fine, uninspectable is not.
public enum SandboxMechanism: String, Equatable, Sendable {
    /// `nono run --profile … -- <agent>`: kernel allow-list, default-deny.
    case nono
    /// Cursor's own Seatbelt/Landlock sandbox via `.cursor/sandbox.json`.
    case cursorNative
    /// Claude Code's own sandbox via `.claude/settings.json`.
    case claudeNative
    /// Codex sandboxes, but only from `~/.codex/config.toml`, which is outside
    /// the repository and therefore outside what `offsend sync` may write.
    case codexUserScope
    /// The editor has no sandbox at all.
    case unavailable
}

/// The position a mechanism actually reaches. Egress denial is the only promise
/// every mechanism can keep, so it is the only one `enabled: true` may imply.
public struct SandboxGuarantee: Equatable, Sendable {
    /// Outbound network is default-deny.
    public let egressDenied: Bool
    /// Reads of named paths can be denied. Absent in Cursor and Codex, where
    /// "read-only" means "read everywhere, write nowhere".
    public let readDeniable: Bool

    public init(egressDenied: Bool, readDeniable: Bool) {
        self.egressDenied = egressDenied
        self.readDeniable = readDeniable
    }
}

public struct SandboxTargetPlan: Equatable, Sendable {
    public let target: AIEditorHookTarget
    public let mechanism: SandboxMechanism
    public let guarantee: SandboxGuarantee
    /// Why this mechanism, in one sentence, for `doctor`.
    public let reason: String

    public init(
        target: AIEditorHookTarget,
        mechanism: SandboxMechanism,
        guarantee: SandboxGuarantee,
        reason: String
    ) {
        self.target = target
        self.mechanism = mechanism
        self.guarantee = guarantee
        self.reason = reason
    }
}

/// Resolves `sandbox.enabled` into a per-editor mechanism.
///
/// The order is deterministic: a CLI agent can be wrapped by `nono` when it is
/// installed, because wrapping happens at process launch; an IDE cannot, since
/// sandboxing `Cursor.app` as a whole would break indexing and extensions.
/// Everything else falls back to the editor's own sandbox.
public enum SandboxMechanismResolver {
    /// Editors Offsend can launch through a process wrapper.
    private static let cliAgents: Set<AIEditorHookTarget> = [.claude, .codex]

    public static func plan(
        targets: [AIEditorHookTarget],
        nonoAvailable: Bool
    ) -> [SandboxTargetPlan] {
        targets.map { plan(target: $0, nonoAvailable: nonoAvailable) }
    }

    public static func plan(
        target: AIEditorHookTarget,
        nonoAvailable: Bool
    ) -> SandboxTargetPlan {
        if cliAgents.contains(target), nonoAvailable {
            return SandboxTargetPlan(
                target: target,
                mechanism: .nono,
                guarantee: SandboxGuarantee(egressDenied: true, readDeniable: true),
                reason: "nono is installed and \(target.rawValue) is a CLI agent, so it can be wrapped at launch"
            )
        }
        switch target {
        case .cursor:
            return SandboxTargetPlan(
                target: target,
                mechanism: .cursorNative,
                guarantee: SandboxGuarantee(egressDenied: true, readDeniable: false),
                reason: "Cursor runs as an IDE, so its own sandbox is the only option; it has no read-deny"
            )
        case .claude:
            return SandboxTargetPlan(
                target: target,
                mechanism: .claudeNative,
                guarantee: SandboxGuarantee(egressDenied: true, readDeniable: true),
                reason: "nono is not installed; Claude Code's own sandbox denies egress and named reads"
            )
        case .codex:
            return SandboxTargetPlan(
                target: target,
                mechanism: .codexUserScope,
                guarantee: SandboxGuarantee(egressDenied: true, readDeniable: false),
                reason: "Codex reads only ~/.codex/config.toml, outside the repository Offsend writes"
            )
        case .windsurf:
            return SandboxTargetPlan(
                target: target,
                mechanism: .unavailable,
                guarantee: SandboxGuarantee(egressDenied: false, readDeniable: false),
                reason: "Windsurf has no sandbox"
            )
        }
    }

    /// True when `nono` is on `PATH`, or when the current process is already
    /// running inside a nono sandbox (`NONO_CAP_FILE` is the only variable nono
    /// sets, so it is also the honest way to detect one).
    public static func nonoAvailable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Bool {
        if let capFile = environment["NONO_CAP_FILE"], !capFile.isEmpty {
            return true
        }
        let path = environment["PATH"] ?? ""
        for directory in path.split(separator: ":") where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent("nono")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return true
            }
        }
        return false
    }
}

/// Splits `ignore.patterns` into what a path-based sandbox can express and what
/// it cannot.
///
/// `denyRead` and nono profiles take paths; `ignore.patterns` is mostly basename
/// globs (`*.pem`, `.env*`). Expanding a glob against the current tree is not an
/// option: the list would be correct only until the next matching file appears,
/// and a stale deny list is worse than a named gap. So globs are reported as
/// uncovered and `doctor` prints them.
public enum SandboxPathCoverage {
    private static let globCharacters = CharacterSet(charactersIn: "*?[]!")

    public static func split(
        patterns: [String]
    ) -> (expressible: [String], uncovered: [String]) {
        var expressible: [String] = []
        var uncovered: [String] = []
        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.rangeOfCharacter(from: globCharacters) != nil {
                uncovered.append(trimmed)
            } else {
                expressible.append(trimmed)
            }
        }
        return (expressible, uncovered)
    }
}
