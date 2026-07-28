import Foundation

public enum AIEditorHookTarget: String, Sendable, CaseIterable {
    case cursor
    case claude
    case windsurf
    case codex

    public var adapter: CheckHookAdapter {
        CheckHookAdapter(rawValue: rawValue) ?? .cursor
    }

    /// Targets a default `hook install` run protects: Cursor and Claude always;
    /// Windsurf/Codex only when there is evidence of use (repo or home config dir).
    public static func detectedTargets(
        repositoryPath: URL,
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) -> [AIEditorHookTarget] {
        func hasDirectory(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        var targets: [AIEditorHookTarget] = [.cursor, .claude]
        if hasDirectory(repositoryPath.appendingPathComponent(".windsurf"))
            || hasDirectory(homeDirectory.appendingPathComponent(".codeium/windsurf")) {
            targets.append(.windsurf)
        }
        if hasDirectory(repositoryPath.appendingPathComponent(".codex"))
            || hasDirectory(homeDirectory.appendingPathComponent(".codex")) {
            targets.append(.codex)
        }
        return targets
    }
}

public enum AIEditorHookInstallerError: Error, Equatable, LocalizedError {
    case writeFailed(path: String, message: String)
    case invalidExistingConfig(path: String)
    case notInstalled(path: String)
    case repositoryPathNotDirectory(path: String)

    public var errorDescription: String? {
        switch self {
        case .writeFailed(let path, let message):
            return "Failed to write \(path): \(message)"
        case .invalidExistingConfig(let path):
            return "Existing config at \(path) is not valid JSON object."
        case .notInstalled(let path):
            return "No Offsend-managed AI hook found at \(path)."
        case .repositoryPathNotDirectory(let path):
            return "Repository path does not exist or is not a directory: \(path)"
        }
    }
}

public struct AIEditorHookInstallResult: Equatable, Sendable {
    public let target: AIEditorHookTarget
    public let configPath: String
    /// Legacy repo-local wrapper path. New installs invoke the trusted CLI directly.
    public let wrapperPath: String?
    public let readWrapperPath: String?
    public let shellWrapperPath: String?
    public let mcpWrapperPath: String?
    public let subagentWrapperPath: String?
    public let mcpResponseWrapperPath: String?
    public let hookPolicy: CheckHookPolicy
    public let command: String
    public let withReadGate: Bool
    public let withWriteGate: Bool
    public let withArtifactAudit: Bool
    public let withShellGate: Bool
    public let withShellAudit: Bool
    public let withMCPGate: Bool
    public let withSubagentGate: Bool
    public let withMCPResponseGate: Bool

    public init(
        target: AIEditorHookTarget,
        configPath: String,
        wrapperPath: String? = nil,
        readWrapperPath: String? = nil,
        shellWrapperPath: String? = nil,
        mcpWrapperPath: String? = nil,
        subagentWrapperPath: String? = nil,
        mcpResponseWrapperPath: String? = nil,
        hookPolicy: CheckHookPolicy,
        command: String,
        withReadGate: Bool = false,
        withWriteGate: Bool = false,
        withArtifactAudit: Bool = false,
        withShellGate: Bool = false,
        withShellAudit: Bool = false,
        withMCPGate: Bool = false,
        withSubagentGate: Bool = false,
        withMCPResponseGate: Bool = false
    ) {
        self.target = target
        self.configPath = configPath
        self.wrapperPath = wrapperPath
        self.readWrapperPath = readWrapperPath
        self.shellWrapperPath = shellWrapperPath
        self.mcpWrapperPath = mcpWrapperPath
        self.subagentWrapperPath = subagentWrapperPath
        self.mcpResponseWrapperPath = mcpResponseWrapperPath
        self.hookPolicy = hookPolicy
        self.command = command
        self.withReadGate = withReadGate
        self.withWriteGate = withWriteGate
        self.withArtifactAudit = withArtifactAudit
        self.withShellGate = withShellGate
        self.withShellAudit = withShellAudit
        self.withMCPGate = withMCPGate
        self.withSubagentGate = withSubagentGate
        self.withMCPResponseGate = withMCPResponseGate
    }
}

/// Status of an Offsend-managed AI-editor hook installation for one target.
public struct AIEditorHookTargetStatus: Equatable, Sendable {
    public let installed: Bool
    public let configPath: String
    public let broken: Bool
    /// True when the config still executes a legacy `.offsend/hooks/*.sh` file.
    public let usesWorkspaceWrappers: Bool
    /// Config references the read-gate wrapper (`check-read.sh`).
    public let readGate: Bool
    /// Config references the Grep gate (`--grep-gate`). Cursor only.
    public let grepGate: Bool
    /// Config invokes the semantic pre-write gate for Edit/Write.
    public let writeGate: Bool
    /// Config records metadata after agent writes to executable trust surfaces.
    public let artifactAudit: Bool
    /// Config references the shell-gate wrapper (`check-shell.sh`).
    public let shellGate: Bool
    /// Config scans shell output after execution (observational only).
    public let shellAudit: Bool
    /// Config references the MCP-gate wrapper (`check-mcp.sh`).
    public let mcpGate: Bool
    /// Config references the subagent-gate wrapper (`check-subagent.sh`). Cursor only.
    public let subagentGate: Bool
    /// Config references the MCP-response-gate wrapper (`check-mcp-out.sh`).
    public let mcpResponseGate: Bool
    /// The response wrapper is attached to an event capable of replacing MCP output.
    public let mcpResponseReplacement: Bool

    public init(
        installed: Bool,
        configPath: String,
        broken: Bool,
        usesWorkspaceWrappers: Bool = false,
        readGate: Bool = false,
        grepGate: Bool = false,
        writeGate: Bool = false,
        artifactAudit: Bool = false,
        shellGate: Bool = false,
        shellAudit: Bool = false,
        mcpGate: Bool = false,
        subagentGate: Bool = false,
        mcpResponseGate: Bool = false,
        mcpResponseReplacement: Bool = false
    ) {
        self.installed = installed
        self.configPath = configPath
        self.broken = broken
        self.usesWorkspaceWrappers = usesWorkspaceWrappers
        self.readGate = readGate
        self.grepGate = grepGate
        self.writeGate = writeGate
        self.artifactAudit = artifactAudit
        self.shellGate = shellGate
        self.shellAudit = shellAudit
        self.mcpGate = mcpGate
        self.subagentGate = subagentGate
        self.mcpResponseGate = mcpResponseGate
        self.mcpResponseReplacement = mcpResponseReplacement
    }
}

/// Installs Offsend-managed AI-editor hooks that invoke the installed CLI directly.
public struct AIEditorHookInstaller: Sendable {
    public static let managedMarker = "offsend-managed-ai-hook"
    public static let managedCommandMarker = "OFFSEND_MANAGED_HOOK=1"
    public static let wrapperRelativePath = ".offsend/hooks/check-prompt.sh"
    public static let readWrapperRelativePath = ".offsend/hooks/check-read.sh"
    public static let shellWrapperRelativePath = ".offsend/hooks/check-shell.sh"
    public static let mcpWrapperRelativePath = ".offsend/hooks/check-mcp.sh"
    public static let subagentWrapperRelativePath = ".offsend/hooks/check-subagent.sh"
    public static let mcpResponseWrapperRelativePath = ".offsend/hooks/check-mcp-out.sh"
    /// Claude PreToolUse matcher for MCP tools (`mcp__server__tool`).
    public static let claudeMCPMatcher = "mcp__.*"
    /// Cursor generic tool matcher for MCP tools.
    public static let cursorMCPMatcher = "MCP:.*"
    /// Claude file-writing tools. A matcher of only letters, digits and `|` is an
    /// exact-name list, so every tool has to be named: `Edit|Write` would not
    /// match `MultiEdit` or `NotebookEdit`.
    public static let claudeWriteMatcher = "Edit|MultiEdit|NotebookEdit|Write"
    /// Cursor file-writing tools. `Delete` is included because removing a hook
    /// config or Git file is as effective as rewriting it; `Edit` is kept for
    /// builds that still expose it under the Claude-compatible name.
    public static let cursorWriteMatcher = "Write|Edit|Delete"
    /// Cursor Task tool — defense-in-depth alongside `subagentStart`.
    public static let cursorTaskMatcher = "Task"
    /// Cursor Grep/search — content seal cannot rewrite match bodies.
    public static let cursorGrepMatcher = "Grep"
    /// Cursor and Claude support read/shell/MCP gates; Windsurf/Codex do not.
    public static func supportsFileGates(_ target: AIEditorHookTarget) -> Bool {
        target == .cursor || target == .claude
    }
    /// Cursor `subagentStart` only (Claude subagents do not reliably inherit parent hooks).
    public static func supportsSubagentGate(_ target: AIEditorHookTarget) -> Bool {
        target == .cursor
    }
    /// Cursor Grep gate (Claude search is not a separate preToolUse tool here).
    public static func supportsGrepGate(_ target: AIEditorHookTarget) -> Bool {
        target == .cursor
    }

    public static let managedVersion = 7

    public enum WrapperValidation: Equatable, Sendable {
        case ok
        case missingFile
        case notExecutable
        case missingManagedMarker
        case outdatedVersion(found: Int?)
        case unreadable
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public static func defaultHookPolicy(for target: AIEditorHookTarget) -> CheckHookPolicy {
        CheckHookPolicy.defaultPolicy(for: target.adapter)
    }

    public func install(
        target: AIEditorHookTarget,
        repositoryPath: URL,
        cliExecutablePath: String,
        hookPolicy: CheckHookPolicy? = nil,
        force: Bool = false,
        withReadGate: Bool = true,
        withWriteGate: Bool = true,
        withShellGate: Bool = true,
        withShellAudit: Bool = true,
        withMCPGate: Bool = true,
        withSubagentGate: Bool = true,
        withMCPResponseGate: Bool = true,
        /// When true, wrappers omit machine-specific PREFERRED_BIN (portable for git).
        portableWrappers: Bool = false
    ) throws -> AIEditorHookInstallResult {
        let policy = hookPolicy ?? Self.defaultHookPolicy(for: target)
        let root = repositoryPath.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AIEditorHookInstallerError.repositoryPathNotDirectory(path: root.path)
        }

        let gateSupported = Self.supportsFileGates(target)
        let enableReadGate = withReadGate && gateSupported
        let enableGrepGate = withReadGate && Self.supportsGrepGate(target)
        let enableWriteGate = withWriteGate && gateSupported
        let enableArtifactAudit = gateSupported
        let enableShellGate = withShellGate && gateSupported
        let enableShellAudit = withShellAudit && gateSupported
        let enableMCPGate = withMCPGate && gateSupported
        let enableSubagentGate = withSubagentGate && Self.supportsSubagentGate(target)
        let enableMCPResponseGate = withMCPResponseGate && gateSupported
        let executable = portableWrappers
            ? "offsend"
            : managedRuntimeExecutable(preferredCLIPath: cliExecutablePath)
        let command = makeCommand(target: target, hookPolicy: policy, executable: executable)
        let configURL = configURL(for: target, repositoryPath: root)

        _ = try loadJSONObject(at: configURL)

        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        switch target {
        case .cursor:
            try mergeCursorConfig(
                command: command,
                readCommand: enableReadGate ? makeReadCommand(target: target, executable: executable) : nil,
                grepCommand: enableGrepGate ? makeGrepCommand(target: target, executable: executable) : nil,
                writeCommand: enableWriteGate ? makeWriteCommand(target: target, executable: executable) : nil,
                artifactAuditCommand: enableArtifactAudit
                    ? makeArtifactAuditCommand(target: target, executable: executable)
                    : nil,
                shellCommand: enableShellGate ? makeShellCommand(target: target, executable: executable) : nil,
                shellAuditCommand: enableShellAudit
                    ? makeShellAuditCommand(target: target, executable: executable)
                    : nil,
                mcpCommand: enableMCPGate ? makeMCPCommand(target: target, executable: executable) : nil,
                subagentCommand: enableSubagentGate ? makeSubagentCommand(target: target, executable: executable) : nil,
                mcpResponseCommand: enableMCPResponseGate ? makeMCPResponseCommand(target: target, executable: executable) : nil,
                at: configURL
            )
        case .windsurf:
            try mergeWindsurfConfig(command: command, at: configURL)
        case .codex:
            try mergeCodexConfig(command: command, at: configURL)
        case .claude:
            try mergeClaudeSettings(
                command: command,
                readCommand: enableReadGate ? makeReadCommand(target: target, executable: executable) : nil,
                writeCommand: enableWriteGate ? makeWriteCommand(target: target, executable: executable) : nil,
                artifactAuditCommand: enableArtifactAudit
                    ? makeArtifactAuditCommand(target: target, executable: executable)
                    : nil,
                shellCommand: enableShellGate ? makeShellCommand(target: target, executable: executable) : nil,
                shellAuditCommand: enableShellAudit
                    ? makeShellAuditCommand(target: target, executable: executable)
                    : nil,
                mcpCommand: enableMCPGate ? makeMCPCommand(target: target, executable: executable) : nil,
                mcpResponseCommand: enableMCPResponseGate ? makeMCPResponseCommand(target: target, executable: executable) : nil,
                at: configURL
            )
        }

        if !enableReadGate {
            cleanupUnusedReadWrapper(repositoryPath: root)
        }
        if !enableShellGate {
            cleanupUnusedShellWrapper(repositoryPath: root)
        }
        if !enableMCPGate {
            cleanupUnusedMCPWrapper(repositoryPath: root)
        }
        if !enableSubagentGate {
            cleanupUnusedSubagentWrapper(repositoryPath: root)
        }
        if !enableMCPResponseGate {
            cleanupUnusedMCPResponseWrapper(repositoryPath: root)
        }
        cleanupUnusedWrapper(relativePath: Self.wrapperRelativePath, repositoryPath: root)
        cleanupUnusedReadWrapper(repositoryPath: root)
        cleanupUnusedShellWrapper(repositoryPath: root)
        cleanupUnusedMCPWrapper(repositoryPath: root)
        cleanupUnusedSubagentWrapper(repositoryPath: root)
        cleanupUnusedMCPResponseWrapper(repositoryPath: root)

        return AIEditorHookInstallResult(
            target: target,
            configPath: configURL.path,
            hookPolicy: policy,
            command: command,
            withReadGate: enableReadGate,
            withWriteGate: enableWriteGate,
            withArtifactAudit: enableArtifactAudit,
            withShellGate: enableShellGate,
            withShellAudit: enableShellAudit,
            withMCPGate: enableMCPGate,
            withSubagentGate: enableSubagentGate,
            withMCPResponseGate: enableMCPResponseGate
        )
    }

    /// Removes `.offsend/hooks/check-read.sh` when no target config still references it.
    public func cleanupUnusedReadWrapper(repositoryPath: URL) {
        cleanupUnusedWrapper(relativePath: Self.readWrapperRelativePath, repositoryPath: repositoryPath)
    }

    /// Removes `.offsend/hooks/check-shell.sh` when no target config still references it.
    public func cleanupUnusedShellWrapper(repositoryPath: URL) {
        cleanupUnusedWrapper(relativePath: Self.shellWrapperRelativePath, repositoryPath: repositoryPath)
    }

    /// Removes `.offsend/hooks/check-mcp.sh` when no target config still references it.
    public func cleanupUnusedMCPWrapper(repositoryPath: URL) {
        cleanupUnusedWrapper(relativePath: Self.mcpWrapperRelativePath, repositoryPath: repositoryPath)
    }

    /// Removes `.offsend/hooks/check-subagent.sh` when no target config still references it.
    public func cleanupUnusedSubagentWrapper(repositoryPath: URL) {
        cleanupUnusedWrapper(relativePath: Self.subagentWrapperRelativePath, repositoryPath: repositoryPath)
    }

    /// Removes `.offsend/hooks/check-mcp-out.sh` when no target config still references it.
    public func cleanupUnusedMCPResponseWrapper(repositoryPath: URL) {
        cleanupUnusedWrapper(relativePath: Self.mcpResponseWrapperRelativePath, repositoryPath: repositoryPath)
    }

    private func cleanupUnusedWrapper(relativePath: String, repositoryPath: URL) {
        let root = repositoryPath.standardizedFileURL
        let stillUsed = AIEditorHookTarget.allCases.contains { target in
            let url = configURL(for: target, repositoryPath: root)
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return Self.configTextReferences(contents, relativePath: relativePath)
        }
        if !stillUsed {
            let wrapperURL = root.appendingPathComponent(relativePath)
            if isManagedWrapper(at: wrapperURL) {
                try? fileManager.removeItem(at: wrapperURL)
            }
        }
    }

    /// True when raw config text references `relativePath`, including JSON `\/` escapes.
    public static func configTextReferences(_ contents: String, relativePath: String) -> Bool {
        if contents.contains(relativePath) { return true }
        // JSONSerialization may escape `/` as `\/` (pre-withoutEscapingSlashes writes).
        let escaped = relativePath.replacingOccurrences(of: "/", with: "\\/")
        return contents.contains(escaped)
    }

    public func uninstall(
        target: AIEditorHookTarget,
        repositoryPath: URL
    ) throws {
        let root = repositoryPath.standardizedFileURL
        let configURL = configURL(for: target, repositoryPath: root)
        guard fileManager.fileExists(atPath: configURL.path) else {
            throw AIEditorHookInstallerError.notInstalled(path: configURL.path)
        }

        let removed: Bool
        switch target {
        case .cursor:
            let promptRemoved = try removeManagedFromEventArray(at: configURL, event: "beforeSubmitPrompt")
            let readRemoved = try removeManagedFromEventArray(at: configURL, event: "beforeReadFile")
            let writeRemoved = try removeManagedFromEventArray(at: configURL, event: "preToolUse")
            let auditRemoved = try removeManagedFromEventArray(at: configURL, event: "afterFileEdit")
            let shellRemoved = try removeManagedFromEventArray(at: configURL, event: "beforeShellExecution")
            let shellAuditRemoved = try removeManagedFromEventArray(at: configURL, event: "afterShellExecution")
            let mcpRemoved = try removeManagedFromEventArray(at: configURL, event: "beforeMCPExecution")
            let subagentRemoved = try removeManagedFromEventArray(at: configURL, event: "subagentStart")
            let mcpResponseRemoved = try removeManagedFromEventArray(at: configURL, event: "afterMCPExecution")
            let postToolRemoved = try removeManagedFromEventArray(at: configURL, event: "postToolUse")
            removed = promptRemoved || readRemoved || writeRemoved || auditRemoved || shellRemoved || shellAuditRemoved
                || mcpRemoved || subagentRemoved || mcpResponseRemoved || postToolRemoved
        case .windsurf:
            removed = try removeManagedFromEventArray(at: configURL, event: "pre_user_prompt")
        case .codex:
            removed = try removeManagedNested(at: configURL, event: "UserPromptSubmit")
        case .claude:
            let promptRemoved = try removeManagedNested(at: configURL, event: "UserPromptSubmit")
            let toolRemoved = try removeManagedNested(at: configURL, event: "PreToolUse")
            let postToolRemoved = try removeManagedNested(at: configURL, event: "PostToolUse")
            removed = promptRemoved || toolRemoved || postToolRemoved
        }

        guard removed else {
            throw AIEditorHookInstallerError.notInstalled(path: configURL.path)
        }

        // Keep shared wrappers if any other target still references them.
        let stillUsed = AIEditorHookTarget.allCases.contains { other in
            status(target: other, repositoryPath: root).installed
        }
        if !stillUsed {
            let wrapperURL = root.appendingPathComponent(Self.wrapperRelativePath)
            if isManagedWrapper(at: wrapperURL) {
                try? fileManager.removeItem(at: wrapperURL)
            }
        }
        cleanupUnusedReadWrapper(repositoryPath: root)
        cleanupUnusedShellWrapper(repositoryPath: root)
        cleanupUnusedMCPWrapper(repositoryPath: root)
        cleanupUnusedSubagentWrapper(repositoryPath: root)
        cleanupUnusedMCPResponseWrapper(repositoryPath: root)
    }

    public func status(
        target: AIEditorHookTarget,
        repositoryPath: URL
    ) -> AIEditorHookTargetStatus {
        let url = configURL(for: target, repositoryPath: repositoryPath)
        guard fileManager.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return AIEditorHookTargetStatus(
                installed: false,
                configPath: url.path,
                broken: false
            )
        }
        let usesWorkspaceWrappers = Self.configTextReferences(contents, relativePath: Self.wrapperRelativePath)
            || Self.configTextReferences(contents, relativePath: Self.readWrapperRelativePath)
            || Self.configTextReferences(contents, relativePath: Self.shellWrapperRelativePath)
            || Self.configTextReferences(contents, relativePath: Self.mcpWrapperRelativePath)
            || Self.configTextReferences(contents, relativePath: Self.subagentWrapperRelativePath)
            || Self.configTextReferences(contents, relativePath: Self.mcpResponseWrapperRelativePath)
        let installed = usesWorkspaceWrappers || containsManagedHookEntry(contents)
        let promptWrapperUsed = Self.configTextReferences(contents, relativePath: Self.wrapperRelativePath)
        let promptURL = repositoryPath.appendingPathComponent(Self.wrapperRelativePath)
        let promptOK = !promptWrapperUsed || validateWrapper(at: promptURL) == .ok
        let readWrapperUsed = Self.configTextReferences(contents, relativePath: Self.readWrapperRelativePath)
        let readUsed = readWrapperUsed
            || managedConfig(contents, containsFlag: "--read-gate")
        let writeUsed = managedConfig(contents, containsFlag: "--write-gate")
        let artifactAuditUsed = managedConfig(contents, containsFlag: "--artifact-audit")
        let readURL = repositoryPath.appendingPathComponent(Self.readWrapperRelativePath)
        let readOK = !readWrapperUsed || validateWrapper(at: readURL) == .ok
        let shellWrapperUsed = Self.configTextReferences(contents, relativePath: Self.shellWrapperRelativePath)
        let shellUsed = shellWrapperUsed
            || managedConfig(contents, containsFlag: "--shell-gate")
        let shellURL = repositoryPath.appendingPathComponent(Self.shellWrapperRelativePath)
        let shellOK = !shellWrapperUsed || validateWrapper(at: shellURL) == .ok
        let shellAuditUsed = managedConfig(contents, containsFlag: "--shell-audit")
        let mcpWrapperUsed = Self.configTextReferences(contents, relativePath: Self.mcpWrapperRelativePath)
        let mcpUsed = mcpWrapperUsed
            || managedConfig(contents, containsFlag: "--mcp-gate")
        let mcpURL = repositoryPath.appendingPathComponent(Self.mcpWrapperRelativePath)
        let mcpOK = !mcpWrapperUsed || validateWrapper(at: mcpURL) == .ok
        let subagentWrapperUsed = Self.configTextReferences(contents, relativePath: Self.subagentWrapperRelativePath)
        let subagentUsed = subagentWrapperUsed
            || managedConfig(contents, containsFlag: "--subagent-gate")
        let subagentURL = repositoryPath.appendingPathComponent(Self.subagentWrapperRelativePath)
        let subagentOK = !subagentWrapperUsed || validateWrapper(at: subagentURL) == .ok
        let mcpResponseWrapperUsed = Self.configTextReferences(
            contents,
            relativePath: Self.mcpResponseWrapperRelativePath
        )
        let mcpResponseUsed = mcpResponseWrapperUsed
            || managedConfig(contents, containsFlag: "--mcp-response-gate")
        let mcpResponseURL = repositoryPath.appendingPathComponent(Self.mcpResponseWrapperRelativePath)
        let mcpResponseOK = !mcpResponseWrapperUsed || validateWrapper(at: mcpResponseURL) == .ok
        let mcpResponseReplacement = mcpResponseUsed
            && configUsesReplacementEvent(contents: contents, target: target)
        return AIEditorHookTargetStatus(
            installed: installed,
            configPath: url.path,
            broken: installed && (!promptOK || !readOK || !shellOK || !mcpOK || !subagentOK || !mcpResponseOK),
            usesWorkspaceWrappers: usesWorkspaceWrappers,
            readGate: readUsed,
            grepGate: managedConfig(contents, containsFlag: "--grep-gate"),
            writeGate: writeUsed,
            artifactAudit: artifactAuditUsed,
            shellGate: shellUsed,
            shellAudit: shellAuditUsed,
            mcpGate: mcpUsed,
            subagentGate: subagentUsed,
            mcpResponseGate: mcpResponseUsed,
            mcpResponseReplacement: mcpResponseReplacement
        )
    }

    private func configUsesReplacementEvent(
        contents: String,
        target: AIEditorHookTarget
    ) -> Bool {
        guard let data = contents.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }
        switch target {
        case .cursor:
            let entries = hooks["postToolUse"] as? [[String: Any]] ?? []
            return entries.contains { isMCPResponseHookObject($0) }
        case .claude:
            let groups = hooks["PostToolUse"] as? [[String: Any]] ?? []
            return groups.contains { group in
                let nested = group["hooks"] as? [[String: Any]] ?? []
                return nested.contains { isMCPResponseHookObject($0) }
            }
        case .windsurf, .codex:
            return false
        }
    }

    private func isMCPResponseHookObject(_ object: [String: Any]) -> Bool {
        guard let command = object["command"] as? String else { return false }
        return command.contains(Self.mcpResponseWrapperRelativePath)
            || (command.contains(Self.managedCommandMarker) && command.contains("--mcp-response-gate"))
    }

    /// True when the config still holds a managed hook entry. The `_offsend`
    /// metadata block carries the marker too, so matching the raw text alone
    /// reports a healthy install for a config whose hook entries were all
    /// removed — exactly what an agent disabling the gates would leave behind.
    private func containsManagedHookEntry(_ contents: String) -> Bool {
        guard let data = contents.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] else {
            // Codex and Windsurf configs are not JSON; the command marker is the
            // only thing to go on there.
            return contents.contains(Self.managedCommandMarker)
        }
        return containsManagedCommand(hooks)
    }

    private func containsManagedCommand(_ value: Any) -> Bool {
        if let object = value as? [String: Any] {
            return isManagedHookObject(object) || object.values.contains(where: containsManagedCommand)
        }
        if let array = value as? [Any] {
            return array.contains(where: containsManagedCommand)
        }
        return false
    }

    private func managedConfig(_ contents: String, containsFlag flag: String) -> Bool {
        contents.contains(Self.managedCommandMarker) && contents.contains(flag)
    }

    /// Validates a repo-local wrapper script (marker, version, executable bit).
    public func validateWrapper(at url: URL) -> WrapperValidation {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missingFile
        }
        guard fileManager.isExecutableFile(atPath: url.path) else {
            return .notExecutable
        }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return .unreadable
        }
        guard let foundVersion = Self.parseManagedVersion(in: contents) else {
            return .missingManagedMarker
        }
        if foundVersion < Self.managedVersion {
            return .outdatedVersion(found: foundVersion)
        }
        return .ok
    }

    public static func parseManagedVersion(in script: String) -> Int? {
        let prefix = "# \(managedMarker) v"
        for line in script.split(separator: "\n", omittingEmptySubsequences: false).prefix(2) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }
            let suffix = trimmed.dropFirst(prefix.count)
            let digits = suffix.prefix(while: \.isNumber)
            guard !digits.isEmpty, suffix.dropFirst(digits.count).first.map({ $0.isWhitespace }) ?? true else {
                continue
            }
            return Int(digits)
        }
        return nil
    }

    public static func wrapperValidationMessage(_ validation: WrapperValidation, path: String) -> String {
        switch validation {
        case .ok:
            return "\(path): ok"
        case .missingFile:
            return "\(path): missing"
        case .notExecutable:
            return "\(path): not executable"
        case .missingManagedMarker:
            return "\(path): missing Offsend managed marker (tampered or foreign script)"
        case .outdatedVersion(let found):
            if let found {
                return "\(path): wrapper v\(found) outdated (expected v\(managedVersion)); re-run hook install"
            }
            return "\(path): wrapper version missing; re-run hook install"
        case .unreadable:
            return "\(path): unreadable"
        }
    }

    public func makeCommand(
        target: AIEditorHookTarget,
        hookPolicy: CheckHookPolicy,
        executable: String = "offsend"
    ) -> String {
        "\(Self.managedCommandMarker) \(executable) check --adapter \(target.adapter.rawValue) "
            + "--hook-policy \(hookPolicy.rawValue) --secrets-only --no-notify"
    }

    public func makeReadCommand(target: AIEditorHookTarget, executable: String = "offsend") -> String {
        "\(Self.managedCommandMarker) \(executable) check --adapter \(target.adapter.rawValue) "
            + "--read-gate --no-notify"
    }

    public func makeWriteCommand(target: AIEditorHookTarget, executable: String = "offsend") -> String {
        "\(Self.managedCommandMarker) \(executable) check --adapter \(target.adapter.rawValue) "
            + "--write-gate --no-notify"
    }

    public func makeArtifactAuditCommand(
        target: AIEditorHookTarget,
        executable: String = "offsend"
    ) -> String {
        "\(Self.managedCommandMarker) \(executable) check --adapter \(target.adapter.rawValue) "
            + "--artifact-audit --no-notify"
    }

    public func makeShellCommand(target: AIEditorHookTarget, executable: String = "offsend") -> String {
        "\(Self.managedCommandMarker) \(executable) check --adapter \(target.adapter.rawValue) "
            + "--shell-gate --no-notify"
    }

    public func makeShellAuditCommand(
        target: AIEditorHookTarget,
        executable: String = "offsend"
    ) -> String {
        "\(Self.managedCommandMarker) \(executable) check --adapter \(target.adapter.rawValue) "
            + "--shell-audit --secrets-only"
    }

    public func makeMCPCommand(target: AIEditorHookTarget, executable: String = "offsend") -> String {
        "\(Self.managedCommandMarker) \(executable) check --adapter \(target.adapter.rawValue) "
            + "--mcp-gate --secrets-only --no-notify"
    }

    public func makeGrepCommand(target: AIEditorHookTarget, executable: String = "offsend") -> String {
        "\(Self.managedCommandMarker) \(executable) check --adapter \(target.adapter.rawValue) "
            + "--grep-gate --secrets-only --no-notify"
    }

    public func makeSubagentCommand(target: AIEditorHookTarget, executable: String = "offsend") -> String {
        "\(Self.managedCommandMarker) \(executable) check --adapter \(target.adapter.rawValue) "
            + "--subagent-gate --secrets-only --no-notify"
    }

    public func makeMCPResponseCommand(target: AIEditorHookTarget, executable: String = "offsend") -> String {
        "\(Self.managedCommandMarker) \(executable) check --adapter \(target.adapter.rawValue) "
            + "--mcp-response-gate --secrets-only --no-notify"
    }

    /// Keep local installs stable across package-manager path changes without
    /// reintroducing an agent-writable wrapper in the repository.
    private func managedRuntimeExecutable(preferredCLIPath: String) -> String {
        let resolver = #"BIN="$1"; shift; if [ ! -x "$BIN" ]; then BIN="$(command -v offsend 2>/dev/null || true)"; fi; if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then echo "offsend: executable not found; install CLI or re-run hook install" >&2; exit 127; fi; exec "$BIN" "$@""#
        return "sh -c \(shellQuote(resolver)) sh \(shellQuote(preferredCLIPath))"
    }

    public func configURL(for target: AIEditorHookTarget, repositoryPath: URL) -> URL {
        let root = repositoryPath.standardizedFileURL
        switch target {
        case .cursor:
            return root.appendingPathComponent(".cursor/hooks.json")
        case .claude:
            return root.appendingPathComponent(".claude/settings.json")
        case .windsurf:
            // Workspace-level Cascade hooks (merged with ~/.codeium/windsurf/hooks.json).
            return root.appendingPathComponent(".windsurf/hooks.json")
        case .codex:
            return root.appendingPathComponent(".codex/hooks.json")
        }
    }

    // MARK: - Legacy wrapper migration

    // Read/remove support stays until existing installations have migrated.
    private func isManagedWrapper(at url: URL) -> Bool {
        guard let script = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return Self.parseManagedVersion(in: script) != nil
    }

    // MARK: - Merge configs

    private func mergeCursorConfig(
        command: String,
        readCommand: String?,
        grepCommand: String?,
        writeCommand: String?,
        artifactAuditCommand: String?,
        shellCommand: String?,
        shellAuditCommand: String?,
        mcpCommand: String?,
        subagentCommand: String?,
        mcpResponseCommand: String?,
        at url: URL
    ) throws {
        var root = try loadJSONObject(at: url) ?? ["version": 1]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let event = "beforeSubmitPrompt"
        var entries = (hooks[event] as? [[String: Any]]) ?? []
        entries.removeAll { isManagedHookObject($0) }
        entries.append(managedCursorEntry(command: command))
        hooks[event] = entries

        setManagedCursorGate(&hooks, event: "beforeReadFile", command: readCommand)
        setManagedCursorGate(
            &hooks,
            event: "preToolUse",
            command: writeCommand,
            failClosed: true,
            matcher: Self.cursorWriteMatcher
        )
        setManagedCursorGate(
            &hooks,
            event: "preToolUse",
            command: subagentCommand,
            failClosed: true,
            matcher: Self.cursorTaskMatcher
        )
        setManagedCursorGate(
            &hooks,
            event: "preToolUse",
            command: grepCommand,
            failClosed: true,
            matcher: Self.cursorGrepMatcher
        )
        setManagedCursorGate(
            &hooks,
            event: "afterFileEdit",
            command: artifactAuditCommand
        )
        // The shell-gate hard-denies control-plane operations (Git execution
        // config, privileged daemons, environment poisoning), so a crashed or
        // timed-out hook must not silently drop those denials. The read-gate
        // above stays fail-open on purpose: it is friction against reading
        // secrets, and blocking every file read on a broken hook costs more than
        // it protects.
        setManagedCursorGate(
            &hooks,
            event: "beforeShellExecution",
            command: shellCommand,
            failClosed: true
        )
        // Observational: there is no decision to lose, so a crashed audit hook
        // must not block the command it can only report on.
        setManagedCursorGate(
            &hooks,
            event: "afterShellExecution",
            command: shellAuditCommand
        )
        // Security-critical: fail closed when the MCP hook crashes or times out.
        setManagedCursorGate(&hooks, event: "beforeMCPExecution", command: mcpCommand, failClosed: true)
        setManagedCursorGate(&hooks, event: "subagentStart", command: subagentCommand, failClosed: true)
        // Remove the legacy observe-only hook and use the generic event that
        // can replace MCP output before the model consumes it.
        setManagedCursorGate(&hooks, event: "afterMCPExecution", command: nil)
        setManagedCursorGate(
            &hooks,
            event: "postToolUse",
            command: mcpResponseCommand,
            matcher: Self.cursorMCPMatcher
        )

        root["hooks"] = hooks
        root["_offsend"] = managedMetadata(event: event)
        try writeJSON(root, to: url)
    }

    /// Adds/refreshes the managed entry for a gate event, or removes it when `command` is nil.
    /// When `matcher` is set, only the managed entry with the same matcher is replaced,
    /// so multiple managed `preToolUse` hooks (Write / Task / Grep) can coexist.
    private func setManagedCursorGate(
        _ hooks: inout [String: Any],
        event: String,
        command: String?,
        failClosed: Bool = false,
        matcher: String? = nil
    ) {
        var entries = (hooks[event] as? [[String: Any]]) ?? []
        entries.removeAll { entry in
            guard isManagedHookObject(entry) else { return false }
            return (entry["matcher"] as? String) == matcher
        }
        if let command {
            entries.append(
                managedCursorEntry(command: command, failClosed: failClosed, matcher: matcher)
            )
            hooks[event] = entries
        } else if entries.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = entries
        }
    }

    private func mergeWindsurfConfig(command: String, at url: URL) throws {
        var root = try loadJSONObject(at: url) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let event = "pre_user_prompt"
        var entries = (hooks[event] as? [[String: Any]]) ?? []
        entries.removeAll { isManagedHookObject($0) }
        entries.append([
            "command": command,
            "show_output": true,
        ])
        hooks[event] = entries
        root["hooks"] = hooks
        root["_offsend"] = managedMetadata(event: event)
        try writeJSON(root, to: url)
    }

    private func mergeCodexConfig(command: String, at url: URL) throws {
        var root = try loadJSONObject(at: url) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let event = "UserPromptSubmit"
        var groups = (hooks[event] as? [[String: Any]]) ?? []
        groups = groups.compactMap { group -> [String: Any]? in
            guard var nested = group["hooks"] as? [[String: Any]] else { return group }
            nested.removeAll { isManagedHookObject($0) }
            guard !nested.isEmpty else { return nil }
            var copy = group
            copy["hooks"] = nested
            return copy
        }
        groups.append([
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                    "timeoutSec": CheckHookLimits.recommendedTimeoutSeconds,
                    "statusMessage": "Offsend prompt check",
                ],
            ],
        ])
        hooks[event] = groups
        root["hooks"] = hooks
        root["_offsend"] = managedMetadata(event: event)
        try writeJSON(root, to: url)
    }

    private func mergeClaudeSettings(
        command: String,
        readCommand: String?,
        writeCommand: String?,
        artifactAuditCommand: String?,
        shellCommand: String?,
        shellAuditCommand: String?,
        mcpCommand: String?,
        mcpResponseCommand: String?,
        at url: URL
    ) throws {
        var root = try loadJSONObject(at: url) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let event = "UserPromptSubmit"
        var groups = (hooks[event] as? [[String: Any]]) ?? []
        groups = removeManagedFromGroups(groups)
        groups.append([
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                    "timeout": CheckHookLimits.recommendedTimeoutSeconds,
                ],
            ],
        ])
        hooks[event] = groups

        let toolEvent = "PreToolUse"
        var toolGroups = removeManagedFromGroups((hooks[toolEvent] as? [[String: Any]]) ?? [])
        if let readCommand {
            toolGroups.append(managedClaudeToolGroup(matcher: "Read", command: readCommand))
        }
        if let writeCommand {
            toolGroups.append(
                managedClaudeToolGroup(matcher: Self.claudeWriteMatcher, command: writeCommand)
            )
        }
        if let shellCommand {
            toolGroups.append(managedClaudeToolGroup(matcher: "Bash", command: shellCommand))
        }
        if let mcpCommand {
            toolGroups.append(managedClaudeToolGroup(matcher: Self.claudeMCPMatcher, command: mcpCommand))
        }
        if toolGroups.isEmpty {
            hooks.removeValue(forKey: toolEvent)
        } else {
            hooks[toolEvent] = toolGroups
        }

        // PostToolUse on MCP tools can rewrite the response (updatedToolOutput),
        // so seal mode replaces secrets before the model sees them.
        let postToolEvent = "PostToolUse"
        var postToolGroups = removeManagedFromGroups((hooks[postToolEvent] as? [[String: Any]]) ?? [])
        if let mcpResponseCommand {
            postToolGroups.append(
                managedClaudeToolGroup(matcher: Self.claudeMCPMatcher, command: mcpResponseCommand)
            )
        }
        if let artifactAuditCommand {
            postToolGroups.append(
                managedClaudeToolGroup(matcher: Self.claudeWriteMatcher, command: artifactAuditCommand)
            )
        }
        if let shellAuditCommand {
            postToolGroups.append(
                managedClaudeToolGroup(matcher: "Bash", command: shellAuditCommand)
            )
        }
        if postToolGroups.isEmpty {
            hooks.removeValue(forKey: postToolEvent)
        } else {
            hooks[postToolEvent] = postToolGroups
        }

        root["hooks"] = hooks
        root["_offsend"] = managedMetadata(event: event)
        try writeJSON(root, to: url)
    }

    private func removeManagedFromGroups(_ groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group -> [String: Any]? in
            guard var nested = group["hooks"] as? [[String: Any]] else { return group }
            nested.removeAll { isManagedHookObject($0) }
            guard !nested.isEmpty else { return nil }
            var copy = group
            copy["hooks"] = nested
            return copy
        }
    }

    private func managedClaudeToolGroup(matcher: String, command: String) -> [String: Any] {
        [
            "matcher": matcher,
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                    "timeout": CheckHookLimits.recommendedTimeoutSeconds,
                ],
            ],
        ]
    }

    // MARK: - Remove

    private func removeManagedFromEventArray(at url: URL, event: String) throws -> Bool {
        var root = try loadJSONObject(at: url) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        guard var entries = hooks[event] as? [[String: Any]] else {
            return false
        }
        let before = entries.count
        entries.removeAll { isManagedHookObject($0) }
        let removed = entries.count != before
        if entries.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = entries
        }
        root["hooks"] = hooks
        if let meta = root["_offsend"] as? [String: Any],
           (meta["event"] as? String) == event {
            root.removeValue(forKey: "_offsend")
        }
        if hooks.isEmpty, isOffsendOnlyConfig(root) {
            try fileManager.removeItem(at: url)
            return removed
        }
        try writeJSON(root, to: url)
        return removed
    }

    private func removeManagedNested(at url: URL, event: String) throws -> Bool {
        var root = try loadJSONObject(at: url) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        guard var groups = hooks[event] as? [[String: Any]] else {
            return false
        }
        var removed = false
        groups = groups.compactMap { group -> [String: Any]? in
            guard var nested = group["hooks"] as? [[String: Any]] else { return group }
            let before = nested.count
            nested.removeAll { isManagedHookObject($0) }
            if nested.count != before { removed = true }
            guard !nested.isEmpty else { return nil }
            var copy = group
            copy["hooks"] = nested
            return copy
        }
        if groups.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = groups
        }
        root["hooks"] = hooks
        if let meta = root["_offsend"] as? [String: Any],
           (meta["event"] as? String) == event {
            root.removeValue(forKey: "_offsend")
        }
        try writeJSON(root, to: url)
        return removed
    }

    // MARK: - Helpers

    private func managedCursorEntry(
        command: String,
        failClosed: Bool = false,
        matcher: String? = nil
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "command": command,
            "failClosed": failClosed,
            "timeout": CheckHookLimits.recommendedTimeoutSeconds,
        ]
        if let matcher {
            entry["matcher"] = matcher
        }
        return entry
    }

    private func managedMetadata(event: String) -> [String: Any] {
        [
            "managed": true,
            "marker": Self.managedMarker,
            "version": Self.managedVersion,
            "event": event,
        ]
    }

    private func isManagedHookObject(_ object: [String: Any]) -> Bool {
        if let command = object["command"] as? String {
            return command.contains(Self.managedCommandMarker)
                || command.contains(Self.wrapperRelativePath)
                || command.contains(Self.readWrapperRelativePath)
                || command.contains(Self.shellWrapperRelativePath)
                || command.contains(Self.mcpWrapperRelativePath)
                || command.contains(Self.subagentWrapperRelativePath)
                || command.contains(Self.mcpResponseWrapperRelativePath)
                || command.contains(Self.managedMarker)
        }
        return false
    }

    private func isOffsendOnlyConfig(_ root: [String: Any]) -> Bool {
        let keys = Set(root.keys)
        return keys.subtracting(["version", "hooks", "_offsend"]).isEmpty
            && ((root["hooks"] as? [String: Any])?.isEmpty ?? true)
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any]? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dict = object as? [String: Any] else {
                throw AIEditorHookInstallerError.invalidExistingConfig(path: url.path)
            }
            return dict
        } catch let error as AIEditorHookInstallerError {
            throw error
        } catch {
            throw AIEditorHookInstallerError.invalidExistingConfig(path: url.path)
        }
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw AIEditorHookInstallerError.writeFailed(path: url.path, message: error.localizedDescription)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw AIEditorHookInstallerError.writeFailed(path: url.path, message: error.localizedDescription)
        }
    }

    private func shellQuote(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_./:-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
