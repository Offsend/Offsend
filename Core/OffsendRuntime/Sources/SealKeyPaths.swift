import Foundation
import MaskingCore

/// Canonical filesystem locations for CLI seal keys under `~/.offsend/`.
public enum SealKeyPaths {
    public static let homeDirectoryName = ".offsend"
    public static let defaultKeyFileName = "seal.key"
    public static let namedKeysDirectoryName = "keys"
    public static let defaultKeyInstallHint = "offsend keygen --default"

    private static let keyNamePattern = #"^[a-zA-Z0-9._-]{1,64}$"#

    public static func homeBaseDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let home = environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    public static func homeDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        homeBaseDirectory(fileManager: fileManager, environment: environment)
            .appendingPathComponent(homeDirectoryName, isDirectory: true)
    }

    public static func defaultKeyURL(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        homeDirectory(fileManager: fileManager, environment: environment)
            .appendingPathComponent(defaultKeyFileName, isDirectory: false)
    }

    public static func namedKeysDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        homeDirectory(fileManager: fileManager, environment: environment)
            .appendingPathComponent(namedKeysDirectoryName, isDirectory: true)
    }

    public static func namedKeyURL(
        name: String,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        let validated = try validateKeyName(name)
        return namedKeysDirectory(fileManager: fileManager, environment: environment)
            .appendingPathComponent("\(validated).key", isDirectory: false)
    }

    public static func validateKeyName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SealError.invalidKey("key name must not be empty")
        }
        guard trimmed.range(of: keyNamePattern, options: .regularExpression) != nil else {
            throw SealError.invalidKey(
                "key name must be 1–64 characters: letters, digits, '.', '_', or '-'"
            )
        }
        // Reject path-ish / hidden-only names even though the regex allows dots.
        if trimmed == "." || trimmed == ".." || trimmed.hasPrefix(".") {
            throw SealError.invalidKey("key name must not be '.' / '..' or start with '.'")
        }
        return trimmed
    }

    /// Creates `url` if missing. Only applies `0700` to newly created directories under
    /// `~/.offsend/` — never chmods an existing parent (e.g. `/tmp`).
    public static func ensureDirectory(
        at url: URL,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw SealError.invalidKey("path exists and is not a directory: \(url.path)")
            }
            if isManagedPath(url, fileManager: fileManager, environment: environment) {
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
            return
        }

        let managed = isManagedPath(url, fileManager: fileManager, environment: environment)
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: managed ? [.posixPermissions: 0o700] : nil
        )
        // Intermediate parents created above may not get 0700; tighten managed ancestors.
        if managed {
            try tightenManagedDirectoryTree(upTo: url, fileManager: fileManager, environment: environment)
        }
    }

    public static func writeKey(
        _ keyData: Data,
        to url: URL,
        raw: Bool,
        force: Bool,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard keyData.count == SealKeyResolver.keyByteCount else {
            throw SealError.invalidKey("expected 32-byte seal key")
        }

        // Refuse to follow/overwrite through a symlink (confused-deputy / plant-link attacks).
        if isSymlink(at: url, fileManager: fileManager) {
            throw SealError.invalidKey("refusing to write seal key through symlink at \(url.path)")
        }

        if fileManager.fileExists(atPath: url.path), !force {
            throw SealError.invalidKey(
                "seal key already exists at \(url.path); use --force to overwrite, or --name for a separate key"
            )
        }

        try ensureDirectory(
            at: url.deletingLastPathComponent(),
            fileManager: fileManager,
            environment: environment
        )

        let payload: Data
        if raw {
            payload = keyData
        } else {
            payload = Data((keyData.base64EncodedString() + "\n").utf8)
        }

        // Write via exclusive temp + rename so the final file is never world-readable
        // under a transient umask before chmod (unlike Data.write(.atomic) alone).
        try writeKeyFileAtomically(payload, to: url, force: force, fileManager: fileManager)
    }

    private static func isManagedPath(
        _ url: URL,
        fileManager: FileManager,
        environment: [String: String]
    ) -> Bool {
        let managedRoot = homeDirectory(fileManager: fileManager, environment: environment)
            .standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == managedRoot || candidate.hasPrefix(managedRoot + "/")
    }

    private static func isSymlink(at url: URL, fileManager: FileManager) -> Bool {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attrs[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeSymbolicLink
    }

    private static func tightenManagedDirectoryTree(
        upTo url: URL,
        fileManager: FileManager,
        environment: [String: String]
    ) throws {
        let root = homeDirectory(fileManager: fileManager, environment: environment).standardizedFileURL
        var current = url.standardizedFileURL
        while true {
            guard isManagedPath(current, fileManager: fileManager, environment: environment) else { break }
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: current.path)
            if current.path == root.path { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
    }

    private static func writeKeyFileAtomically(
        _ payload: Data,
        to url: URL,
        force: Bool,
        fileManager: FileManager
    ) throws {
        let directory = url.deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).tmp-\(UUID().uuidString)"
        )
        defer { try? fileManager.removeItem(at: tempURL) }

        let created = fileManager.createFile(
            atPath: tempURL.path,
            contents: payload,
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw SealError.invalidKey("could not create temporary key file at \(tempURL.path)")
        }
        // Reinforce in case createFile ignored attributes on this platform.
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)

        if force, fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        do {
            try fileManager.linkItem(at: tempURL, to: url)
            try? fileManager.removeItem(at: tempURL)
        } catch {
            // linkItem fails if destination exists — preserves refuse-overwrite under races.
            if fileManager.fileExists(atPath: url.path) {
                throw SealError.invalidKey(
                    "seal key already exists at \(url.path); use --force to overwrite, or --name for a separate key"
                )
            }
            throw SealError.invalidKey("could not write seal key to \(url.path)")
        }
    }

    public static func countNamedKeys(fileManager: FileManager = .default) -> Int {
        let directory = namedKeysDirectory(fileManager: fileManager)
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        return contents.filter { $0.pathExtension == "key" }.count
    }

    /// Returns a warning when the key file mode is wider than `0600`, otherwise `nil`.
    public static func insecurePermissionWarning(
        at url: URL,
        fileManager: FileManager = .default
    ) -> String? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let permissions = attrs[.posixPermissions] as? NSNumber else {
            return nil
        }
        let mode = permissions.uint16Value & 0o777
        let groupOrOther = mode & ~0o600
        guard groupOrOther != 0 else { return nil }
        return String(
            format: "%@ mode is %03o (expected 0600; group/other bits are set)",
            url.path,
            mode
        )
    }
}

/// User-facing hints when seal-copy fails in hooks / `check --hook-policy block`.
public enum SealAvailabilityHint {
    public static func hasExplicitKeySource(key: String?, keyFile: String?, keyName: String?) -> Bool {
        key != nil || keyFile != nil || keyName != nil
    }

    /// Short stderr line (includes trailing newline).
    public static func stderrMessage(
        error: Error,
        key: String?,
        keyFile: String?,
        keyName: String?
    ) -> String {
        "offsend: seal unavailable; \(detail(error: error, explicit: hasExplicitKeySource(key: key, keyFile: keyFile, keyName: keyName)))\n"
    }

    /// Suffix for hook `userMessage` (no leading space required by caller beyond their own).
    public static func userMessageDetail(
        error: Error,
        key: String?,
        keyFile: String?,
        keyName: String?
    ) -> String {
        detail(error: error, explicit: hasExplicitKeySource(key: key, keyFile: keyFile, keyName: keyName))
    }

    private static func detail(error: Error, explicit: Bool) -> String {
        if let sealError = error as? SealError {
            switch sealError {
            case .invalidKey(let reason):
                if explicit {
                    return sanitize(reason)
                }
                if reason.contains(SealKeyPaths.defaultKeyInstallHint) || reason.contains("provide --key") {
                    return "run: \(SealKeyPaths.defaultKeyInstallHint)"
                }
                return sanitize(reason)
            default:
                return explicit
                    ? "key resolved but seal failed (\(sealError.localizedDescription))"
                    : "run: \(SealKeyPaths.defaultKeyInstallHint)"
            }
        }
        if explicit {
            return "check --key-file / --key-name (or seal engine error)"
        }
        return "run: \(SealKeyPaths.defaultKeyInstallHint)"
    }

    /// Avoid echoing absolute paths that might contain usernames when reason is already long;
    /// keep short actionable text.
    private static func sanitize(_ reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 160 { return trimmed }
        return String(trimmed.prefix(157)) + "..."
    }
}
