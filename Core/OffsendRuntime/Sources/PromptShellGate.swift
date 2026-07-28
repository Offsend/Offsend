import Foundation
import WorkspacePolicyCore

public struct PromptShellGateDecision: Equatable, Sendable {
    public let command: String
    /// Sensitive-looking path tokens found in the command.
    public let suspiciousPaths: [String]
    public let reason: String
    /// Control-plane mutations must be denied in agent shells, not merely confirmed.
    public let deny: Bool

    /// True only when there are no findings. A hard deny with an empty label
    /// list (invalid / oversized input) is still not allowed.
    public var allowed: Bool { suspiciousPaths.isEmpty && !deny }

    public init(command: String, suspiciousPaths: [String], reason: String, deny: Bool = false) {
        self.command = command
        self.suspiciousPaths = suspiciousPaths
        self.reason = reason
        self.deny = deny
    }
}

/// Best-effort gate for Cursor `beforeShellExecution` / Claude `PreToolUse` (Bash).
/// Tokenizes the command and flags sensitive path tokens (same heuristics as the
/// read-gate path heuristics, including symlink targets when the path exists).
/// Does not parse full shell grammar and never reads file contents. Sensitive-path
/// findings follow `context.shell.mode` (`deny` by default; `ask` when configured
/// and trusted). Control-plane findings always deny.
public enum PromptShellGate {
    public static func evaluate(
        json: String,
        adapter: CheckHookAdapter,
        classifier: ExecutableArtifactClassifier? = nil,
        shellConfig: OffsendProjectShellConfig? = nil,
        protectedPatterns: [String] = [],
        projectRoot: URL? = nil,
        defaultCWD: String? = nil
    ) throws -> PromptShellGateDecision {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        guard let command = extractCommand(from: root, adapter: adapter) else {
            throw PromptHookInputError.invalidJSON
        }
        let cwd = (root["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultCWD
        return evaluate(
            command: command,
            cwd: cwd,
            classifier: classifier,
            shellConfig: shellConfig,
            protectedPatterns: protectedPatterns,
            projectRoot: projectRoot
        )
    }

    /// Deny for unrecognized / unparseable shell-gate hook input (fail-closed).
    public static func invalidInputDecision() -> PromptShellGateDecision {
        PromptShellGateDecision(
            command: "",
            suspiciousPaths: [],
            reason: "Offsend: unrecognized shell-gate hook input denied.",
            deny: true
        )
    }

    /// Deny for hook input over the stdin byte limit (fail-closed).
    public static func oversizedStdinDecision() -> PromptShellGateDecision {
        PromptShellGateDecision(
            command: "",
            suspiciousPaths: [],
            reason: "Offsend: blocked this shell command — hook input exceeds the "
                + "\(CheckHookLimits.maxStdinBytes)-byte safety limit and cannot be scanned.",
            deny: true
        )
    }

    /// One reason the command was flagged. A command can trip several gates at
    /// once, and reporting only the first would send the user round after round
    /// of edits.
    private struct Finding {
        let labels: [String]
        let reason: String
        let deny: Bool

        init(label: String, reason: String, deny: Bool) {
            self.init(labels: [label], reason: reason, deny: deny)
        }

        init(labels: [String], reason: String, deny: Bool) {
            self.labels = labels
            self.reason = reason
            self.deny = deny
        }
    }

    public static func evaluate(
        command: String,
        cwd: String? = nil,
        classifier: ExecutableArtifactClassifier? = nil,
        shellConfig: OffsendProjectShellConfig? = nil,
        protectedPatterns: [String] = [],
        projectRoot: URL? = nil
    ) -> PromptShellGateDecision {
        let mode = OffsendShellGateMode.effective(shellConfig?.mode)
        let modeDenies = mode == .deny
        var findings: [Finding] = []

        if let mutation = policyMutation(in: command) {
            findings.append(Finding(
                label: "offsend policy \(mutation)",
                reason: "Offsend: agents cannot \(mutation) the trusted policy snapshot. "
                    + "Review .offsend.yml and run this command yourself in an interactive terminal.",
                deny: true
            ))
        }
        if let environment = EnvironmentPoisoningClassifier.classify(command: command, cwd: cwd) {
            let denied = environment.risk == .deny || modeDenies
            findings.append(Finding(
                label: "environment \(environment.variable)",
                reason: denied
                    ? "Offsend blocked the \(environment.variable) override because \(environment.reason). Set execution-sensitive environment manually outside the agent session."
                    : "Offsend: \(environment.variable) override changes the host execution environment. Confirm explicitly before running this command.",
                deny: denied
            ))
        }
        if let gitConfig = GitConfigInvocationClassifier.classify(command: command) {
            findings.append(Finding(
                label: "git config \(gitConfig.key)",
                reason: "Offsend blocked this command because it performs a Git config "
                    + "\(gitConfig.operation) on execution-sensitive key \(gitConfig.key). "
                    + "Review and change Git execution settings manually outside the agent session.",
                deny: true
            ))
        }
        if let daemon = PrivilegedDaemonInvocationClassifier.classify(command: command) {
            let denied = daemon.risk == .deny || modeDenies
            findings.append(Finding(
                label: "\(daemon.surface): \(daemon.operation)",
                reason: denied
                    ? "Offsend blocked \(daemon.operation) through \(daemon.surface) because the daemon executes outside the agent sandbox. Run and review this operation yourself in an interactive terminal."
                    : "Offsend: command mutates \(daemon.surface) through \(daemon.operation). Confirm explicitly before allowing host-side daemon effects.",
                deny: denied
            ))
        }
        // `offsend unseal` restores sealed plaintext; the agent must not quietly
        // unseal what the read/MCP gates just sealed.
        if referencesUnseal(command) {
            findings.append(Finding(
                label: "offsend unseal",
                reason: modeDenies
                    ? "Offsend blocked `offsend unseal` — it restores sealed secrets to plaintext. "
                        + "Run unseal yourself outside the agent session."
                    : "Offsend: command runs `offsend unseal` — it restores sealed secrets to plaintext. "
                        + "Confirm before running; unseal output belongs to the user, not the agent context.",
                deny: modeDenies
            ))
        }

        let candidates = pathCandidates(in: command)
        if let classifier {
            findings.append(contentsOf: artifactFindings(
                candidates: candidates,
                cwd: cwd,
                classifier: classifier,
                modeDenies: modeDenies
            ))
        }
        findings.append(contentsOf: sensitivePathFindings(
            candidates: candidates,
            cwd: cwd,
            modeDenies: modeDenies,
            protectedPatterns: protectedPatterns,
            projectRoot: projectRoot
        ))

        guard !findings.isEmpty else {
            return PromptShellGateDecision(command: command, suspiciousPaths: [], reason: "")
        }
        // Denials first: they decide the outcome, so they should lead the message.
        let ordered = findings.filter(\.deny) + findings.filter { !$0.deny }
        var seen = Set<String>()
        let labels = ordered.flatMap(\.labels).filter { seen.insert($0.lowercased()).inserted }
        return PromptShellGateDecision(
            command: command,
            suspiciousPaths: labels,
            reason: ordered.map(\.reason).joined(separator: " "),
            deny: ordered.contains(where: \.deny)
        )
    }

    private static func artifactFindings(
        candidates: [String],
        cwd: String?,
        classifier: ExecutableArtifactClassifier,
        modeDenies: Bool
    ) -> [Finding] {
        var findings: [Finding] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard let artifact = classifier.classify(path: candidate, cwd: cwd),
                  seen.insert(artifact.path).inserted else { continue }
            let name = URL(fileURLWithPath: artifact.path).lastPathComponent
            switch artifact.enforcement {
            case .deny:
                findings.append(Finding(
                    label: artifact.path,
                    reason: "Offsend blocked this command because it directly targets executable workspace configuration (\(name)). Review and edit this trust surface manually.",
                    deny: true
                ))
            case .denyWhenContentExecutable:
                // A shell command carries no parsed content, so the gate cannot
                // tell an ordinary settings edit from an injected interpreter
                // path. Mode deny blocks; ask confirms.
                findings.append(Finding(
                    label: artifact.path,
                    reason: modeDenies
                        ? "Offsend blocked this command because it targets editor configuration (\(name)) that can carry interpreter paths, terminal profiles, or task commands. Review and edit this trust surface manually."
                        : "Offsend: command targets editor configuration (\(name)) that can carry "
                            + "interpreter paths, terminal profiles, or task commands. Confirm before running.",
                    deny: modeDenies
                ))
            case .observe:
                continue
            }
        }
        return findings
    }

    private static func sensitivePathFindings(
        candidates: [String],
        cwd: String?,
        modeDenies: Bool,
        protectedPatterns: [String],
        projectRoot: URL?
    ) -> [Finding] {
        var seen = Set<String>()
        var suspicious: [String] = []
        for candidate in candidates {
            let name = firstSuspiciousBasename(in: candidate, cwd: cwd)
                ?? protectedPathBasename(
                    candidate,
                    cwd: cwd,
                    patterns: protectedPatterns,
                    projectRoot: projectRoot
                )
            guard let name else { continue }
            if seen.insert(name.lowercased()).inserted {
                suspicious.append(name)
            }
        }
        guard !suspicious.isEmpty else { return [] }
        let names = suspicious.joined(separator: ", ")
        return [Finding(
            labels: suspicious,
            reason: modeDenies
                ? "Offsend blocked this command because it touches sensitive path (\(names)). "
                    + "Secrets can fuel further tool use — prefer env vars / AI ignore files."
                : "Offsend: command touches sensitive path (\(names)). "
                    + "Confirm before running — secrets can fuel further tool use.",
            deny: modeDenies
        )]
    }

    /// `ignore.patterns` is the source-of-truth context boundary. A path under
    /// that boundary must be shell-sensitive even when its basename is generic
    /// (`fixtures/`, `private-data/`, etc.).
    private static func protectedPathBasename(
        _ candidate: String,
        cwd: String?,
        patterns: [String],
        projectRoot: URL?
    ) -> String? {
        guard !patterns.isEmpty, let projectRoot else { return nil }
        let root = projectRoot.standardizedFileURL.path
        for absolute in PromptReadGate.sensitivityCheckPaths(for: candidate, cwd: cwd) {
            guard absolute == root || absolute.hasPrefix(root + "/") else { continue }
            let relative = absolute == root ? "" : String(absolute.dropFirst(root.count + 1))
            guard !relative.isEmpty,
                  IgnorePatternPathMatcher.isIgnored(
                      relativePath: relative,
                      ignoreLines: patterns
                  ) else { continue }
            return URL(fileURLWithPath: absolute).lastPathComponent
        }
        return nil
    }

    /// True when the command invokes `offsend … unseal` (any path to the binary).
    static func referencesUnseal(_ command: String) -> Bool {
        offsendInvocations(in: command).contains { $0.contains("unseal") }
    }

    /// Returns `trust` or `forget` for Offsend policy control-plane mutations.
    static func policyMutation(in command: String) -> String? {
        for arguments in offsendInvocations(in: command) {
            guard let policyIndex = arguments.firstIndex(of: "policy"),
                  policyIndex + 1 < arguments.count else { continue }
            let mutation = arguments[policyIndex + 1]
            if mutation == "trust" || mutation == "forget" { return mutation }
        }
        return nil
    }

    /// Arguments (without argv[0]) of every `offsend` invocation in the command.
    private static func offsendInvocations(in command: String) -> [[String]] {
        ShellInvocationExtractor.invocations(in: command)
            .filter { $0.executableName == "offsend" }
            .map { Array($0.arguments.dropFirst()) }
    }

    /// Raw token first (covers `~/.ssh/…` without expanding), then absolute + symlink target.
    private static func firstSuspiciousBasename(in candidate: String, cwd: String?) -> String? {
        var paths = [candidate]
        for resolved in PromptReadGate.sensitivityCheckPaths(for: candidate, cwd: cwd)
            where !paths.contains(resolved) {
            paths.append(resolved)
        }
        for path in paths where PromptAttachmentAdvisor.isSuspicious(path: path) {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return nil
    }

    public static func extractCommand(from root: [String: Any], adapter: CheckHookAdapter) -> String? {
        switch adapter {
        case .cursor:
            if let command = root["command"] as? String, !command.isEmpty { return command }
            return nil
        case .claude:
            if let toolInput = root["tool_input"] as? [String: Any],
               let command = toolInput["command"] as? String, !command.isEmpty {
                return command
            }
            if let command = root["command"] as? String, !command.isEmpty { return command }
            return nil
        case .windsurf, .codex:
            return nil
        }
    }

    /// Lexed tokens, including those inside nested shell / interpreter scripts and
    /// `$(…)` bodies. Redirections are unglued from their target and `VAR=value` /
    /// `--flag=value` contribute the value part. Opaque tokens also contribute
    /// quoted / path-shaped substrings (`open('cert.pem')`). Adjacent static
    /// string concatenations in interpreter payloads (`"c"+"ert"+".pem"`) are
    /// joined before the sweep so path heuristics see the reconstructed name.
    static func pathCandidates(in command: String) -> [String] {
        let strippable = CharacterSet(charactersIn: "()<>,;[]{}")
        var candidates: [String] = []
        var seen = Set<String>()
        func append(_ raw: String) {
            var candidate = strippingRedirection(raw).trimmingCharacters(in: strippable)
            if let equals = candidate.firstIndex(of: "="),
               equals != candidate.startIndex {
                candidate = String(candidate[candidate.index(after: equals)...])
                    .trimmingCharacters(in: strippable)
            }
            // `$HOME/.ssh/id_rsa` → keep; bare `$f` is not a path candidate.
            if candidate.hasPrefix("$") {
                if let slash = candidate.firstIndex(of: "/") {
                    candidate = String(candidate[slash...])
                } else if candidate.hasPrefix("${"),
                          let close = candidate.firstIndex(of: "}"),
                          close < candidate.endIndex,
                          candidate[candidate.index(after: close)...].first == "/" {
                    candidate = String(candidate[candidate.index(after: close)...])
                } else {
                    return
                }
            }
            guard !candidate.isEmpty, !candidate.hasPrefix("-") else { return }
            if seen.insert(candidate).inserted {
                candidates.append(candidate)
            }
        }

        for rawToken in ShellInvocationExtractor.allTokens(in: command) {
            append(rawToken)
            for embedded in embeddedPathFragments(in: rawToken) {
                append(embedded)
            }
        }
        return candidates
    }

    /// Path-like fragments buried inside opaque tokens (`open('cert.pem')`).
    private static func embeddedPathFragments(in token: String) -> [String] {
        var fragments: [String] = []
        let characters = Array(token)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "'" || character == "\"" {
                let quote = character
                index += 1
                var fragment = ""
                while index < characters.count, characters[index] != quote {
                    fragment.append(characters[index])
                    index += 1
                }
                if !fragment.isEmpty { fragments.append(fragment) }
                if index < characters.count { index += 1 }
                continue
            }
            index += 1
        }
        return fragments
    }

    /// Drops a leading redirection operator so `2>>.envrc` yields `.envrc`,
    /// while an ordinary name such as `2024-notes.txt` is left alone.
    private static func strippingRedirection(_ rawToken: String) -> String {
        var index = rawToken.startIndex
        while index < rawToken.endIndex, rawToken[index].isNumber {
            index = rawToken.index(after: index)
        }
        guard index < rawToken.endIndex, rawToken[index] == "<" || rawToken[index] == ">" else {
            return rawToken
        }
        while index < rawToken.endIndex, "<>&".contains(rawToken[index]) {
            index = rawToken.index(after: index)
        }
        return String(rawToken[index...])
    }
}

public enum PromptShellGateRenderer {
    /// Findings produce `ask` or `deny` depending on `context.shell.mode` and
    /// whether the finding is control-plane (always deny).
    public static func render(
        decision: PromptShellGateDecision,
        adapter: CheckHookAdapter
    ) -> CheckHookAdapterOutput {
        switch adapter {
        case .cursor:
            if decision.allowed {
                return CheckHookAdapterOutput(
                    stdout: jsonObject(["permission": "allow"]),
                    stderr: "",
                    exitCode: 0
                )
            }
            if decision.deny {
                return CheckHookAdapterOutput(
                    stdout: jsonObject([
                        "permission": "deny",
                        "user_message": decision.reason,
                        "agent_message": decision.reason,
                    ]),
                    stderr: decision.reason + "\n",
                    exitCode: 0
                )
            }
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "permission": "ask",
                    "user_message": decision.reason,
                    "agent_message": "The command references sensitive files (\(decision.suspiciousPaths.joined(separator: ", "))). Ask the user before reading secret material — credentials can fuel further tool use. Prefer env vars / AI ignore files.",
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        case .claude:
            if decision.allowed {
                return CheckHookAdapterOutput(stdout: "{}", stderr: "", exitCode: 0)
            }
            return CheckHookAdapterOutput(
                stdout: jsonObject([
                    "hookSpecificOutput": [
                        "hookEventName": "PreToolUse",
                        "permissionDecision": decision.deny ? "deny" : "ask",
                        "permissionDecisionReason": decision.reason,
                    ],
                ]),
                stderr: decision.reason + "\n",
                exitCode: 0
            )
        case .windsurf, .codex:
            return CheckHookAdapterOutput(stdout: "", stderr: "", exitCode: 0)
        }
    }

    private static func jsonObject(_ object: [String: Any]) -> String {
        CheckHookResponseRenderer.encodeJSONObject(object)
    }
}
