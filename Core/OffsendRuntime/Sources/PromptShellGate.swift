import Foundation

public struct PromptShellGateDecision: Equatable, Sendable {
    public let command: String
    /// Sensitive-looking path tokens found in the command.
    public let suspiciousPaths: [String]
    public let reason: String
    /// Control-plane mutations must be denied in agent shells, not merely confirmed.
    public let deny: Bool

    public var allowed: Bool { suspiciousPaths.isEmpty }

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
/// Does not parse shell grammar and never reads file contents; findings ask for
/// user confirmation instead of blocking.
public enum PromptShellGate {
    public static func evaluate(
        json: String,
        adapter: CheckHookAdapter,
        classifier: ExecutableArtifactClassifier? = nil
    ) throws -> PromptShellGateDecision {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }
        guard let command = extractCommand(from: root, adapter: adapter) else {
            throw PromptHookInputError.invalidJSON
        }
        let cwd = (root["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return evaluate(command: command, cwd: cwd, classifier: classifier)
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
        classifier: ExecutableArtifactClassifier? = nil
    ) -> PromptShellGateDecision {
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
            let denied = environment.risk == .deny
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
            let denied = daemon.risk == .deny
            findings.append(Finding(
                label: "\(daemon.surface): \(daemon.operation)",
                reason: denied
                    ? "Offsend blocked \(daemon.operation) through \(daemon.surface) because the daemon executes outside the agent sandbox. Run and review this operation yourself in an interactive terminal."
                    : "Offsend: command mutates \(daemon.surface) through \(daemon.operation). Confirm explicitly before allowing host-side daemon effects.",
                deny: denied
            ))
        }
        // `offsend unseal` restores sealed plaintext; the agent must not quietly
        // unseal what the read/MCP gates just sealed. Ask the user first.
        if referencesUnseal(command) {
            findings.append(Finding(
                label: "offsend unseal",
                reason: "Offsend: command runs `offsend unseal` — it restores sealed secrets to plaintext. "
                    + "Confirm before running; unseal output belongs to the user, not the agent context.",
                deny: false
            ))
        }

        let candidates = pathCandidates(in: command)
        if let classifier {
            findings.append(contentsOf: artifactFindings(
                candidates: candidates,
                cwd: cwd,
                classifier: classifier
            ))
        }
        findings.append(contentsOf: sensitivePathFindings(candidates: candidates, cwd: cwd))

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
        classifier: ExecutableArtifactClassifier
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
                // path. Ask instead of guessing.
                findings.append(Finding(
                    label: artifact.path,
                    reason: "Offsend: command targets editor configuration (\(name)) that can carry "
                        + "interpreter paths, terminal profiles, or task commands. Confirm before running.",
                    deny: false
                ))
            case .observe:
                continue
            }
        }
        return findings
    }

    private static func sensitivePathFindings(candidates: [String], cwd: String?) -> [Finding] {
        var seen = Set<String>()
        var suspicious: [String] = []
        for candidate in candidates {
            guard let name = firstSuspiciousBasename(in: candidate, cwd: cwd) else { continue }
            if seen.insert(name.lowercased()).inserted {
                suspicious.append(name)
            }
        }
        guard !suspicious.isEmpty else { return [] }
        return [Finding(
            labels: suspicious,
            reason: "Offsend: command touches sensitive path (\(suspicious.joined(separator: ", "))). "
                + "Confirm before running — secrets can fuel further tool use.",
            deny: false
        )]
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

    /// Lexed tokens, including those inside nested `-c` scripts. Redirections are
    /// unglued from their target and `VAR=value` / `--flag=value` contribute the
    /// value part.
    static func pathCandidates(in command: String) -> [String] {
        let strippable = CharacterSet(charactersIn: "()<>,")
        var candidates: [String] = []
        for rawToken in ShellInvocationExtractor.allTokens(in: command) {
            var candidate = strippingRedirection(rawToken).trimmingCharacters(in: strippable)
            if let equals = candidate.firstIndex(of: "=") {
                candidate = String(candidate[candidate.index(after: equals)...])
                    .trimmingCharacters(in: strippable)
            }
            guard !candidate.isEmpty, !candidate.hasPrefix("-") else { continue }
            candidates.append(candidate)
        }
        return candidates
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
    /// Findings produce `ask` (user confirmation), never a hard deny.
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
