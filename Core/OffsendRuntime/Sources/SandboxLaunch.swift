import Foundation

/// Builds the argv Offsend uses to start an AI editor under the sandbox
/// configured in `.offsend.yml`.
///
/// `nono` wraps only CLI agents (`claude`, `codex`), and only when
/// `sandbox.enabled` is true **and** nono is available. Otherwise the bare
/// binary (or Cursor via `open`) is launched — native editor sandboxes, if any,
/// already live in the files `offsend sync` wrote.
public enum SandboxLaunch {
    public struct Invocation: Equatable, Sendable {
        /// Program basename or absolute path (`nono`, `claude`, `codex`, `/usr/bin/open`).
        public let program: String
        public let arguments: [String]
        /// One-line display for stderr / doctor.
        public let display: String
        public let usesNono: Bool
        /// Mechanism that would apply when sandbox is enabled; `nil` when policy is off.
        public let mechanism: SandboxMechanism?
        /// Repo-relative nono profile when `usesNono`.
        public let profileRelativePath: String?

        public init(
            program: String,
            arguments: [String],
            display: String,
            usesNono: Bool,
            mechanism: SandboxMechanism?,
            profileRelativePath: String? = nil
        ) {
            self.program = program
            self.arguments = arguments
            self.display = display
            self.usesNono = usesNono
            self.mechanism = mechanism
            self.profileRelativePath = profileRelativePath
        }
    }

    public enum LaunchError: LocalizedError, Equatable, Sendable {
        case unsupportedTarget(String)
        case missingBinary(String)
        case missingNonoProfile(path: String)
        case missingNonoPack(message: String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedTarget(let name):
                return "Unsupported editor for `offsend run`: \(name). Use cursor, claude, or codex."
            case .missingBinary(let name):
                return "Could not find `\(name)` on PATH."
            case .missingNonoProfile(let path):
                return "Missing nono profile at \(path). Run `offsend sync` or `offsend run … --sync` first."
            case .missingNonoPack(let message):
                return message
            }
        }
    }

    /// CLI agent binary name for a target (`claude` / `codex`).
    public static func agentBinary(for target: AIEditorHookTarget) -> String? {
        switch target {
        case .claude: return "claude"
        case .codex: return "codex"
        case .cursor, .windsurf: return nil
        }
    }

    /// Repo-relative path of the generated nono profile.
    public static func nonoProfileRelativePath(for target: AIEditorHookTarget) -> String {
        "\(SandboxSyncService.nonoProfileDirectory)/offsend-\(target.rawValue).json"
    }

    /// Resolve how to launch `target` given the sandbox policy and nono presence.
    ///
    /// Does not look up binaries on PATH — the CLI does that before `exec`.
    public static func invocation(
        target: AIEditorHookTarget,
        sandboxEnabled: Bool,
        nonoAvailable: Bool,
        agentArguments: [String] = [],
        openPath: String? = nil
    ) throws -> Invocation {
        switch target {
        case .windsurf:
            throw LaunchError.unsupportedTarget(target.rawValue)
        case .cursor:
            return cursorInvocation(
                sandboxEnabled: sandboxEnabled,
                openPath: openPath,
                extraArguments: agentArguments
            )
        case .claude, .codex:
            return cliAgentInvocation(
                target: target,
                sandboxEnabled: sandboxEnabled,
                nonoAvailable: nonoAvailable,
                agentArguments: agentArguments
            )
        }
    }

    /// Hint printed by `sync` / `doctor` when the user must start a CLI agent
    /// through nono (or via `offsend run`).
    public static func nonoLaunchHint(for target: AIEditorHookTarget) -> String {
        let relative = nonoProfileRelativePath(for: target)
        let binary = agentBinary(for: target) ?? target.rawValue
        return "Start \(target.rawValue) through the sandbox: "
            + "offsend run \(target.rawValue) "
            + "(or: nono run --profile ./\(relative) --allow-cwd -- \(binary)). "
            + "Offsend writes the profile; it cannot wrap a process that is already running."
    }

    // MARK: - Private

    private static func cursorInvocation(
        sandboxEnabled: Bool,
        openPath: String?,
        extraArguments: [String]
    ) -> Invocation {
        var arguments = ["-a", "Cursor"]
        if let openPath, !openPath.isEmpty {
            arguments.append(openPath)
        }
        arguments.append(contentsOf: extraArguments)
        let display = (["open"] + arguments).joined(separator: " ")
        return Invocation(
            program: "/usr/bin/open",
            arguments: arguments,
            display: display,
            usesNono: false,
            mechanism: sandboxEnabled ? .cursorNative : nil
        )
    }

    private static func cliAgentInvocation(
        target: AIEditorHookTarget,
        sandboxEnabled: Bool,
        nonoAvailable: Bool,
        agentArguments: [String]
    ) -> Invocation {
        let binary = agentBinary(for: target) ?? target.rawValue
        let plan = SandboxMechanismResolver.plan(
            target: target,
            nonoAvailable: nonoAvailable
        )
        // nono only when the policy asks for a sandbox *and* the resolver
        // chose nono for this CLI agent.
        let wrapWithNono = sandboxEnabled && plan.mechanism == .nono
        if wrapWithNono {
            let relative = nonoProfileRelativePath(for: target)
            var arguments = [
                "run",
                "--profile", "./\(relative)",
                "--allow-cwd",
                "--",
                binary,
            ]
            arguments.append(contentsOf: agentArguments)
            let display = (["nono"] + arguments).joined(separator: " ")
            return Invocation(
                program: "nono",
                arguments: arguments,
                display: display,
                usesNono: true,
                mechanism: .nono,
                profileRelativePath: relative
            )
        }

        let display = ([binary] + agentArguments).joined(separator: " ")
        return Invocation(
            program: binary,
            arguments: agentArguments,
            display: display,
            usesNono: false,
            mechanism: sandboxEnabled ? plan.mechanism : nil
        )
    }
}
