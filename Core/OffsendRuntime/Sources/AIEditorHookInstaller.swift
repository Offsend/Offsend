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
    case wrapperAlreadyExists(path: String)

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
        case .wrapperAlreadyExists(let path):
            return "Wrapper already exists at \(path) and is not Offsend-managed. Use --force to overwrite."
        }
    }
}

public struct AIEditorHookInstallResult: Equatable, Sendable {
    public let target: AIEditorHookTarget
    public let configPath: String
    public let wrapperPath: String
    public let readWrapperPath: String?
    public let shellWrapperPath: String?
    public let mcpWrapperPath: String?
    public let subagentWrapperPath: String?
    public let hookPolicy: CheckHookPolicy
    public let command: String
    public let withReadGate: Bool
    public let withShellGate: Bool
    public let withMCPGate: Bool
    public let withSubagentGate: Bool

    public init(
        target: AIEditorHookTarget,
        configPath: String,
        wrapperPath: String,
        readWrapperPath: String? = nil,
        shellWrapperPath: String? = nil,
        mcpWrapperPath: String? = nil,
        subagentWrapperPath: String? = nil,
        hookPolicy: CheckHookPolicy,
        command: String,
        withReadGate: Bool = false,
        withShellGate: Bool = false,
        withMCPGate: Bool = false,
        withSubagentGate: Bool = false
    ) {
        self.target = target
        self.configPath = configPath
        self.wrapperPath = wrapperPath
        self.readWrapperPath = readWrapperPath
        self.shellWrapperPath = shellWrapperPath
        self.mcpWrapperPath = mcpWrapperPath
        self.subagentWrapperPath = subagentWrapperPath
        self.hookPolicy = hookPolicy
        self.command = command
        self.withReadGate = withReadGate
        self.withShellGate = withShellGate
        self.withMCPGate = withMCPGate
        self.withSubagentGate = withSubagentGate
    }
}

/// Status of an Offsend-managed AI-editor hook installation for one target.
public struct AIEditorHookTargetStatus: Equatable, Sendable {
    public let installed: Bool
    public let configPath: String
    public let broken: Bool
    /// Config references the read-gate wrapper (`check-read.sh`).
    public let readGate: Bool
    /// Config references the shell-gate wrapper (`check-shell.sh`).
    public let shellGate: Bool
    /// Config references the MCP-gate wrapper (`check-mcp.sh`).
    public let mcpGate: Bool
    /// Config references the subagent-gate wrapper (`check-subagent.sh`). Cursor only.
    public let subagentGate: Bool

    public init(
        installed: Bool,
        configPath: String,
        broken: Bool,
        readGate: Bool = false,
        shellGate: Bool = false,
        mcpGate: Bool = false,
        subagentGate: Bool = false
    ) {
        self.installed = installed
        self.configPath = configPath
        self.broken = broken
        self.readGate = readGate
        self.shellGate = shellGate
        self.mcpGate = mcpGate
        self.subagentGate = subagentGate
    }
}

/// Installs Offsend-managed AI-editor prompt hooks that call a repo-local wrapper.
public struct AIEditorHookInstaller: Sendable {
    public static let managedMarker = "offsend-managed-ai-hook"
    public static let wrapperRelativePath = ".offsend/hooks/check-prompt.sh"
    public static let readWrapperRelativePath = ".offsend/hooks/check-read.sh"
    public static let shellWrapperRelativePath = ".offsend/hooks/check-shell.sh"
    public static let mcpWrapperRelativePath = ".offsend/hooks/check-mcp.sh"
    public static let subagentWrapperRelativePath = ".offsend/hooks/check-subagent.sh"
    /// Claude PreToolUse matcher for MCP tools (`mcp__server__tool`).
    public static let claudeMCPMatcher = "mcp__.*"
    /// Cursor and Claude support read/shell/MCP gates; Windsurf/Codex do not.
    public static func supportsFileGates(_ target: AIEditorHookTarget) -> Bool {
        target == .cursor || target == .claude
    }
    /// Cursor `subagentStart` only (Claude subagents do not reliably inherit parent hooks).
    public static func supportsSubagentGate(_ target: AIEditorHookTarget) -> Bool {
        target == .cursor
    }

    public static let managedVersion = 2

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
        withShellGate: Bool = true,
        withMCPGate: Bool = true,
        withSubagentGate: Bool = true,
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

        let wrapperURL = root.appendingPathComponent(Self.wrapperRelativePath)
        let gateSupported = Self.supportsFileGates(target)
        let enableReadGate = withReadGate && gateSupported
        let enableShellGate = withShellGate && gateSupported
        let enableMCPGate = withMCPGate && gateSupported
        let enableSubagentGate = withSubagentGate && Self.supportsSubagentGate(target)
        let command = makeCommand(target: target, hookPolicy: policy)
        let configURL = configURL(for: target, repositoryPath: root)
        let readWrapperURL = enableReadGate
            ? root.appendingPathComponent(Self.readWrapperRelativePath)
            : nil
        let shellWrapperURL = enableShellGate
            ? root.appendingPathComponent(Self.shellWrapperRelativePath)
            : nil
        let mcpWrapperURL = enableMCPGate
            ? root.appendingPathComponent(Self.mcpWrapperRelativePath)
            : nil
        let subagentWrapperURL = enableSubagentGate
            ? root.appendingPathComponent(Self.subagentWrapperRelativePath)
            : nil
        let preferredCLIPath = portableWrappers ? "" : cliExecutablePath

        // Validate every existing destination before changing any wrapper.
        _ = try loadJSONObject(at: configURL)
        try validateWrapperDestination(wrapperURL, force: force)
        if let readWrapperURL {
            try validateWrapperDestination(readWrapperURL, force: force)
        }
        if let shellWrapperURL {
            try validateWrapperDestination(shellWrapperURL, force: force)
        }
        if let mcpWrapperURL {
            try validateWrapperDestination(mcpWrapperURL, force: force)
        }
        if let subagentWrapperURL {
            try validateWrapperDestination(subagentWrapperURL, force: force)
        }

        try writeWrapper(to: wrapperURL, preferredCLIPath: preferredCLIPath)
        if let readWrapperURL {
            try writeReadWrapper(to: readWrapperURL, preferredCLIPath: preferredCLIPath)
        }
        if let shellWrapperURL {
            try writeShellWrapper(to: shellWrapperURL, preferredCLIPath: preferredCLIPath)
        }
        if let mcpWrapperURL {
            try writeMCPWrapper(to: mcpWrapperURL, preferredCLIPath: preferredCLIPath)
        }
        if let subagentWrapperURL {
            try writeSubagentWrapper(to: subagentWrapperURL, preferredCLIPath: preferredCLIPath)
        }

        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        switch target {
        case .cursor:
            try mergeCursorConfig(
                command: command,
                readCommand: enableReadGate ? makeReadCommand(target: target) : nil,
                shellCommand: enableShellGate ? makeShellCommand(target: target) : nil,
                mcpCommand: enableMCPGate ? makeMCPCommand(target: target) : nil,
                subagentCommand: enableSubagentGate ? makeSubagentCommand(target: target) : nil,
                at: configURL
            )
        case .windsurf:
            try mergeWindsurfConfig(command: command, at: configURL)
        case .codex:
            try mergeCodexConfig(command: command, at: configURL)
        case .claude:
            try mergeClaudeSettings(
                command: command,
                readCommand: enableReadGate ? makeReadCommand(target: target) : nil,
                shellCommand: enableShellGate ? makeShellCommand(target: target) : nil,
                mcpCommand: enableMCPGate ? makeMCPCommand(target: target) : nil,
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

        return AIEditorHookInstallResult(
            target: target,
            configPath: configURL.path,
            wrapperPath: wrapperURL.path,
            readWrapperPath: readWrapperURL?.path,
            shellWrapperPath: shellWrapperURL?.path,
            mcpWrapperPath: mcpWrapperURL?.path,
            subagentWrapperPath: subagentWrapperURL?.path,
            hookPolicy: policy,
            command: command,
            withReadGate: enableReadGate,
            withShellGate: enableShellGate,
            withMCPGate: enableMCPGate,
            withSubagentGate: enableSubagentGate
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
            let shellRemoved = try removeManagedFromEventArray(at: configURL, event: "beforeShellExecution")
            let mcpRemoved = try removeManagedFromEventArray(at: configURL, event: "beforeMCPExecution")
            let subagentRemoved = try removeManagedFromEventArray(at: configURL, event: "subagentStart")
            removed = promptRemoved || readRemoved || shellRemoved || mcpRemoved || subagentRemoved
        case .windsurf:
            removed = try removeManagedFromEventArray(at: configURL, event: "pre_user_prompt")
        case .codex:
            removed = try removeManagedNested(at: configURL, event: "UserPromptSubmit")
        case .claude:
            let promptRemoved = try removeManagedNested(at: configURL, event: "UserPromptSubmit")
            let toolRemoved = try removeManagedNested(at: configURL, event: "PreToolUse")
            removed = promptRemoved || toolRemoved
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
        let installed = Self.configTextReferences(contents, relativePath: Self.wrapperRelativePath)
            || Self.configTextReferences(contents, relativePath: Self.readWrapperRelativePath)
            || Self.configTextReferences(contents, relativePath: Self.shellWrapperRelativePath)
            || Self.configTextReferences(contents, relativePath: Self.mcpWrapperRelativePath)
            || Self.configTextReferences(contents, relativePath: Self.subagentWrapperRelativePath)
            || contents.contains(Self.managedMarker)
        let promptURL = repositoryPath.appendingPathComponent(Self.wrapperRelativePath)
        let promptOK = validateWrapper(at: promptURL) == .ok
        let readUsed = Self.configTextReferences(contents, relativePath: Self.readWrapperRelativePath)
        let readURL = repositoryPath.appendingPathComponent(Self.readWrapperRelativePath)
        let readOK = !readUsed || validateWrapper(at: readURL) == .ok
        let shellUsed = Self.configTextReferences(contents, relativePath: Self.shellWrapperRelativePath)
        let shellURL = repositoryPath.appendingPathComponent(Self.shellWrapperRelativePath)
        let shellOK = !shellUsed || validateWrapper(at: shellURL) == .ok
        let mcpUsed = Self.configTextReferences(contents, relativePath: Self.mcpWrapperRelativePath)
        let mcpURL = repositoryPath.appendingPathComponent(Self.mcpWrapperRelativePath)
        let mcpOK = !mcpUsed || validateWrapper(at: mcpURL) == .ok
        let subagentUsed = Self.configTextReferences(contents, relativePath: Self.subagentWrapperRelativePath)
        let subagentURL = repositoryPath.appendingPathComponent(Self.subagentWrapperRelativePath)
        let subagentOK = !subagentUsed || validateWrapper(at: subagentURL) == .ok
        return AIEditorHookTargetStatus(
            installed: installed,
            configPath: url.path,
            broken: installed && (!promptOK || !readOK || !shellOK || !mcpOK || !subagentOK),
            readGate: readUsed,
            shellGate: shellUsed,
            mcpGate: mcpUsed,
            subagentGate: subagentUsed
        )
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

    public func makeCommand(target: AIEditorHookTarget, hookPolicy: CheckHookPolicy) -> String {
        let script = Self.wrapperRelativePath
        let args = "\(target.adapter.rawValue) \(hookPolicy.rawValue)"
        switch target {
        case .claude:
            return "\"$CLAUDE_PROJECT_DIR\"/\(script) \(args)"
        case .cursor, .windsurf, .codex:
            return "\(script) \(args)"
        }
    }

    public func makeReadCommand(target: AIEditorHookTarget) -> String {
        let script = Self.readWrapperRelativePath
        switch target {
        case .claude:
            return "\"$CLAUDE_PROJECT_DIR\"/\(script) \(target.adapter.rawValue)"
        case .cursor:
            return "\(script) \(target.adapter.rawValue)"
        case .windsurf, .codex:
            return "\(script) \(target.adapter.rawValue)"
        }
    }

    public func makeShellCommand(target: AIEditorHookTarget) -> String {
        let script = Self.shellWrapperRelativePath
        switch target {
        case .claude:
            return "\"$CLAUDE_PROJECT_DIR\"/\(script) \(target.adapter.rawValue)"
        case .cursor, .windsurf, .codex:
            return "\(script) \(target.adapter.rawValue)"
        }
    }

    public func makeMCPCommand(target: AIEditorHookTarget) -> String {
        let script = Self.mcpWrapperRelativePath
        switch target {
        case .claude:
            return "\"$CLAUDE_PROJECT_DIR\"/\(script) \(target.adapter.rawValue)"
        case .cursor, .windsurf, .codex:
            return "\(script) \(target.adapter.rawValue)"
        }
    }

    public func makeSubagentCommand(target: AIEditorHookTarget) -> String {
        "\(Self.subagentWrapperRelativePath) \(target.adapter.rawValue)"
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

    // MARK: - Wrapper

    private func validateWrapperDestination(_ url: URL, force: Bool) throws {
        guard (try? fileManager.attributesOfItem(atPath: url.path)) != nil else {
            return
        }
        if force {
            return
        }
        guard isManagedWrapper(at: url),
              let script = try? String(contentsOf: url, encoding: .utf8),
              let version = Self.parseManagedVersion(in: script),
              version <= Self.managedVersion else {
            throw AIEditorHookInstallerError.wrapperAlreadyExists(path: url.path)
        }
    }

    private func isManagedWrapper(at url: URL) -> Bool {
        guard let script = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return Self.parseManagedVersion(in: script) != nil
    }

    private func writeWrapper(to url: URL, preferredCLIPath: String) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let script = """
        #!/bin/sh
        # \(Self.managedMarker) v\(Self.managedVersion)
        set -eu
        ADAPTER="${1:?adapter required}"
        POLICY="${2:-advise}"
        PREFERRED_BIN=\(shellQuote(preferredCLIPath))
        OFFSEND_BIN=""
        if [ -x "${PREFERRED_BIN}" ]; then
          OFFSEND_BIN="${PREFERRED_BIN}"
        fi
        if [ -z "${OFFSEND_BIN}" ]; then
          OFFSEND_BIN="$(command -v offsend 2>/dev/null || true)"
        fi
        if [ -z "${OFFSEND_BIN}" ] || [ ! -x "${OFFSEND_BIN}" ]; then
          echo "offsend: executable not found; install CLI or re-run hook install" >&2
          case "$ADAPTER" in
            cursor) echo '{"continue":true}' ;;
            claude|codex) echo '{}' ;;
            windsurf) : ;;
          esac
          exit 0
        fi
        exec "${OFFSEND_BIN}" check --adapter "${ADAPTER}" --hook-policy "${POLICY}" --secrets-only --no-notify
        """
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            throw AIEditorHookInstallerError.writeFailed(path: url.path, message: error.localizedDescription)
        }
    }

    private func writeReadWrapper(to url: URL, preferredCLIPath: String) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let script = """
        #!/bin/sh
        # \(Self.managedMarker) v\(Self.managedVersion) read-gate
        set -eu
        ADAPTER="${1:?adapter required}"
        PREFERRED_BIN=\(shellQuote(preferredCLIPath))
        OFFSEND_BIN=""
        if [ -x "${PREFERRED_BIN}" ]; then
          OFFSEND_BIN="${PREFERRED_BIN}"
        fi
        if [ -z "${OFFSEND_BIN}" ]; then
          OFFSEND_BIN="$(command -v offsend 2>/dev/null || true)"
        fi
        if [ -z "${OFFSEND_BIN}" ] || [ ! -x "${OFFSEND_BIN}" ]; then
          echo "offsend: executable not found; install CLI or re-run hook install" >&2
          case "$ADAPTER" in
            cursor) echo '{"permission":"allow"}' ;;
            claude) echo '{}' ;;
            windsurf) : ;;
          esac
          exit 0
        fi
        exec "${OFFSEND_BIN}" check --adapter "${ADAPTER}" --read-gate --no-notify
        """
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            throw AIEditorHookInstallerError.writeFailed(path: url.path, message: error.localizedDescription)
        }
    }

    private func writeShellWrapper(to url: URL, preferredCLIPath: String) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let script = """
        #!/bin/sh
        # \(Self.managedMarker) v\(Self.managedVersion) shell-gate
        set -eu
        ADAPTER="${1:?adapter required}"
        PREFERRED_BIN=\(shellQuote(preferredCLIPath))
        OFFSEND_BIN=""
        if [ -x "${PREFERRED_BIN}" ]; then
          OFFSEND_BIN="${PREFERRED_BIN}"
        fi
        if [ -z "${OFFSEND_BIN}" ]; then
          OFFSEND_BIN="$(command -v offsend 2>/dev/null || true)"
        fi
        if [ -z "${OFFSEND_BIN}" ] || [ ! -x "${OFFSEND_BIN}" ]; then
          echo "offsend: executable not found; install CLI or re-run hook install" >&2
          case "$ADAPTER" in
            cursor) echo '{"permission":"allow"}' ;;
            claude) echo '{}' ;;
            windsurf) : ;;
          esac
          exit 0
        fi
        exec "${OFFSEND_BIN}" check --adapter "${ADAPTER}" --shell-gate --no-notify
        """
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            throw AIEditorHookInstallerError.writeFailed(path: url.path, message: error.localizedDescription)
        }
    }

    private func writeMCPWrapper(to url: URL, preferredCLIPath: String) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let script = """
        #!/bin/sh
        # \(Self.managedMarker) v\(Self.managedVersion) mcp-gate
        set -eu
        ADAPTER="${1:?adapter required}"
        PREFERRED_BIN=\(shellQuote(preferredCLIPath))
        OFFSEND_BIN=""
        if [ -x "${PREFERRED_BIN}" ]; then
          OFFSEND_BIN="${PREFERRED_BIN}"
        fi
        if [ -z "${OFFSEND_BIN}" ]; then
          OFFSEND_BIN="$(command -v offsend 2>/dev/null || true)"
        fi
        if [ -z "${OFFSEND_BIN}" ] || [ ! -x "${OFFSEND_BIN}" ]; then
          echo "offsend: executable not found; install CLI or re-run hook install" >&2
          case "$ADAPTER" in
            cursor) echo '{"permission":"allow"}' ;;
            claude) echo '{}' ;;
            windsurf) : ;;
          esac
          exit 0
        fi
        exec "${OFFSEND_BIN}" check --adapter "${ADAPTER}" --mcp-gate --secrets-only --no-notify
        """
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            throw AIEditorHookInstallerError.writeFailed(path: url.path, message: error.localizedDescription)
        }
    }

    private func writeSubagentWrapper(to url: URL, preferredCLIPath: String) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let script = """
        #!/bin/sh
        # \(Self.managedMarker) v\(Self.managedVersion) subagent-gate
        set -eu
        ADAPTER="${1:?adapter required}"
        PREFERRED_BIN=\(shellQuote(preferredCLIPath))
        OFFSEND_BIN=""
        if [ -x "${PREFERRED_BIN}" ]; then
          OFFSEND_BIN="${PREFERRED_BIN}"
        fi
        if [ -z "${OFFSEND_BIN}" ]; then
          OFFSEND_BIN="$(command -v offsend 2>/dev/null || true)"
        fi
        if [ -z "${OFFSEND_BIN}" ] || [ ! -x "${OFFSEND_BIN}" ]; then
          echo "offsend: executable not found; install CLI or re-run hook install" >&2
          case "$ADAPTER" in
            cursor) echo '{"permission":"allow"}' ;;
            claude) echo '{}' ;;
            windsurf) : ;;
          esac
          exit 0
        fi
        exec "${OFFSEND_BIN}" check --adapter "${ADAPTER}" --subagent-gate --secrets-only --no-notify
        """
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            throw AIEditorHookInstallerError.writeFailed(path: url.path, message: error.localizedDescription)
        }
    }

    // MARK: - Merge configs

    private func mergeCursorConfig(
        command: String,
        readCommand: String?,
        shellCommand: String?,
        mcpCommand: String?,
        subagentCommand: String?,
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
        setManagedCursorGate(&hooks, event: "beforeShellExecution", command: shellCommand)
        // Security-critical: fail closed when the MCP hook crashes or times out.
        setManagedCursorGate(&hooks, event: "beforeMCPExecution", command: mcpCommand, failClosed: true)
        setManagedCursorGate(&hooks, event: "subagentStart", command: subagentCommand, failClosed: true)

        root["hooks"] = hooks
        root["_offsend"] = managedMetadata(event: event)
        try writeJSON(root, to: url)
    }

    /// Adds/refreshes the managed entry for a gate event, or removes it when `command` is nil.
    private func setManagedCursorGate(
        _ hooks: inout [String: Any],
        event: String,
        command: String?,
        failClosed: Bool = false
    ) {
        if let command {
            var entries = (hooks[event] as? [[String: Any]]) ?? []
            entries.removeAll { isManagedHookObject($0) }
            entries.append(managedCursorEntry(command: command, failClosed: failClosed))
            hooks[event] = entries
        } else if var entries = hooks[event] as? [[String: Any]] {
            entries.removeAll { isManagedHookObject($0) }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
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
        shellCommand: String?,
        mcpCommand: String?,
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
            // Gate Read plus Edit/Write so a prior leaked read cannot be "fixed" via Edit.
            toolGroups.append(
                managedClaudeToolGroup(matcher: "Read|Edit|Write", command: readCommand)
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

    private func managedCursorEntry(command: String, failClosed: Bool = false) -> [String: Any] {
        [
            "command": command,
            "failClosed": failClosed,
            "timeout": CheckHookLimits.recommendedTimeoutSeconds,
        ]
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
            return command.contains(Self.wrapperRelativePath)
                || command.contains(Self.readWrapperRelativePath)
                || command.contains(Self.shellWrapperRelativePath)
                || command.contains(Self.mcpWrapperRelativePath)
                || command.contains(Self.subagentWrapperRelativePath)
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
