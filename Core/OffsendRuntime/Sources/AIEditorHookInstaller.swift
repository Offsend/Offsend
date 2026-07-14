import Foundation

public enum AIEditorHookTarget: String, Sendable, CaseIterable {
    case cursor
    case claude
    case windsurf
    case codex

    public var adapter: CheckHookAdapter {
        CheckHookAdapter(rawValue: rawValue) ?? .cursor
    }
}

public enum AIEditorHookInstallerError: Error, Equatable, LocalizedError {
    case writeFailed(path: String, message: String)
    case invalidExistingConfig(path: String)
    case notInstalled(path: String)

    public var errorDescription: String? {
        switch self {
        case .writeFailed(let path, let message):
            return "Failed to write \(path): \(message)"
        case .invalidExistingConfig(let path):
            return "Existing config at \(path) is not valid JSON object."
        case .notInstalled(let path):
            return "No Offsend-managed AI hook found at \(path)."
        }
    }
}

public struct AIEditorHookInstallResult: Equatable, Sendable {
    public let target: AIEditorHookTarget
    public let configPath: String
    public let wrapperPath: String
    public let readWrapperPath: String?
    public let hookPolicy: CheckHookPolicy
    public let command: String
    public let withReadGate: Bool

    public init(
        target: AIEditorHookTarget,
        configPath: String,
        wrapperPath: String,
        readWrapperPath: String? = nil,
        hookPolicy: CheckHookPolicy,
        command: String,
        withReadGate: Bool = false
    ) {
        self.target = target
        self.configPath = configPath
        self.wrapperPath = wrapperPath
        self.readWrapperPath = readWrapperPath
        self.hookPolicy = hookPolicy
        self.command = command
        self.withReadGate = withReadGate
    }
}

/// Installs Offsend-managed AI-editor prompt hooks that call a repo-local wrapper.
public struct AIEditorHookInstaller: Sendable {
    public static let managedMarker = "offsend-managed-ai-hook"
    public static let wrapperRelativePath = ".offsend/hooks/check-prompt.sh"
    public static let readWrapperRelativePath = ".offsend/hooks/check-read.sh"
    public static let managedVersion = 1

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
        withReadGate: Bool = false
    ) throws -> AIEditorHookInstallResult {
        // Install always rewrites managed wrappers; `force` only affects git pre-commit hooks.
        let policy = hookPolicy ?? Self.defaultHookPolicy(for: target)
        let root = repositoryPath.standardizedFileURL
        let wrapperURL = root.appendingPathComponent(Self.wrapperRelativePath)
        try writeWrapper(to: wrapperURL, preferredCLIPath: cliExecutablePath)

        let enableReadGate = withReadGate && (target == .cursor || target == .claude)
        var readWrapperURL: URL?
        if enableReadGate {
            let url = root.appendingPathComponent(Self.readWrapperRelativePath)
            try writeReadWrapper(to: url, preferredCLIPath: cliExecutablePath)
            readWrapperURL = url
        }

        let command = makeCommand(target: target, hookPolicy: policy)
        let configURL = configURL(for: target, repositoryPath: root)

        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        switch target {
        case .cursor:
            try mergeCursorConfig(
                command: command,
                readCommand: enableReadGate ? makeReadCommand(target: target) : nil,
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
                at: configURL
            )
        }

        if !enableReadGate {
            cleanupUnusedReadWrapper(repositoryPath: root)
        }

        return AIEditorHookInstallResult(
            target: target,
            configPath: configURL.path,
            wrapperPath: wrapperURL.path,
            readWrapperPath: readWrapperURL?.path,
            hookPolicy: policy,
            command: command,
            withReadGate: enableReadGate
        )
    }

    /// Removes `.offsend/hooks/check-read.sh` when no target config still references it.
    public func cleanupUnusedReadWrapper(repositoryPath: URL) {
        let root = repositoryPath.standardizedFileURL
        let stillUsed = AIEditorHookTarget.allCases.contains { target in
            let url = configURL(for: target, repositoryPath: root)
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return contents.contains(Self.readWrapperRelativePath)
        }
        if !stillUsed {
            let readURL = root.appendingPathComponent(Self.readWrapperRelativePath)
            try? fileManager.removeItem(at: readURL)
        }
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
            removed = promptRemoved || readRemoved
        case .windsurf:
            removed = try removeManagedFromEventArray(at: configURL, event: "pre_user_prompt")
        case .codex:
            removed = try removeManagedNested(at: configURL, event: "UserPromptSubmit")
        case .claude:
            let promptRemoved = try removeManagedNested(at: configURL, event: "UserPromptSubmit")
            let readRemoved = try removeManagedNested(at: configURL, event: "PreToolUse")
            removed = promptRemoved || readRemoved
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
            try? fileManager.removeItem(at: wrapperURL)
        }
        cleanupUnusedReadWrapper(repositoryPath: root)
    }

    public func status(
        target: AIEditorHookTarget,
        repositoryPath: URL
    ) -> (installed: Bool, configPath: String, broken: Bool) {
        let url = configURL(for: target, repositoryPath: repositoryPath)
        guard fileManager.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return (false, url.path, false)
        }
        let installed = contents.contains(Self.wrapperRelativePath)
            || contents.contains(Self.readWrapperRelativePath)
            || contents.contains(Self.managedMarker)
        let promptURL = repositoryPath.appendingPathComponent(Self.wrapperRelativePath)
        let promptOK = validateWrapper(at: promptURL) == .ok
        let readUsed = contents.contains(Self.readWrapperRelativePath)
        let readURL = repositoryPath.appendingPathComponent(Self.readWrapperRelativePath)
        let readOK = !readUsed || validateWrapper(at: readURL) == .ok
        return (installed, url.path, installed && (!promptOK || !readOK))
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
        guard contents.contains(Self.managedMarker) else {
            return .missingManagedMarker
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
        for line in script.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }
            let suffix = trimmed.dropFirst(prefix.count)
            let digits = suffix.prefix(while: \.isNumber)
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

    // MARK: - Merge configs

    private func mergeCursorConfig(command: String, readCommand: String?, at url: URL) throws {
        var root = try loadJSONObject(at: url) ?? ["version": 1]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let event = "beforeSubmitPrompt"
        var entries = (hooks[event] as? [[String: Any]]) ?? []
        entries.removeAll { isManagedHookObject($0) }
        entries.append(managedCursorEntry(command: command))
        hooks[event] = entries

        let readEvent = "beforeReadFile"
        if let readCommand {
            var readEntries = (hooks[readEvent] as? [[String: Any]]) ?? []
            readEntries.removeAll { isManagedHookObject($0) }
            readEntries.append(managedCursorEntry(command: readCommand))
            hooks[readEvent] = readEntries
        } else {
            if var readEntries = hooks[readEvent] as? [[String: Any]] {
                readEntries.removeAll { isManagedHookObject($0) }
                if readEntries.isEmpty {
                    hooks.removeValue(forKey: readEvent)
                } else {
                    hooks[readEvent] = readEntries
                }
            }
        }

        root["hooks"] = hooks
        root["_offsend"] = managedMetadata(event: event)
        try writeJSON(root, to: url)
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

    private func mergeClaudeSettings(command: String, readCommand: String?, at url: URL) throws {
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
                    "timeout": CheckHookLimits.recommendedTimeoutSeconds,
                ],
            ],
        ])
        hooks[event] = groups

        let readEvent = "PreToolUse"
        if let readCommand {
            var readGroups = (hooks[readEvent] as? [[String: Any]]) ?? []
            readGroups = readGroups.compactMap { group -> [String: Any]? in
                guard var nested = group["hooks"] as? [[String: Any]] else { return group }
                nested.removeAll { isManagedHookObject($0) }
                guard !nested.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = nested
                return copy
            }
            readGroups.append([
                "matcher": "Read",
                "hooks": [
                    [
                        "type": "command",
                        "command": readCommand,
                        "timeout": CheckHookLimits.recommendedTimeoutSeconds,
                    ],
                ],
            ])
            hooks[readEvent] = readGroups
        } else if var readGroups = hooks[readEvent] as? [[String: Any]] {
            readGroups = readGroups.compactMap { group -> [String: Any]? in
                guard var nested = group["hooks"] as? [[String: Any]] else { return group }
                nested.removeAll { isManagedHookObject($0) }
                guard !nested.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = nested
                return copy
            }
            if readGroups.isEmpty {
                hooks.removeValue(forKey: readEvent)
            } else {
                hooks[readEvent] = readGroups
            }
        }

        root["hooks"] = hooks
        root["_offsend"] = managedMetadata(event: event)
        try writeJSON(root, to: url)
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

    private func managedCursorEntry(command: String) -> [String: Any] {
        [
            "command": command,
            "failClosed": false,
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
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw AIEditorHookInstallerError.invalidExistingConfig(path: url.path)
        }
        return dict
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
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
