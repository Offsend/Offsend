import Foundation

/// Registry packs that supply the base profiles Offsend's generated nono
/// configs `extends`. Without them, `claude-code` / `codex` are not installed
/// (they left the nono binary for the [registry](https://nono.sh/registry)).
///
/// Preferred namespace is `nolabs-ai` (current); `always-further` is accepted
/// during the org migration so existing installs keep working.
public struct NonoPackRequirement: Equatable, Sendable {
    public let target: AIEditorHookTarget
    /// Pack id to recommend in `nono pull` / doctor (`namespace/name`).
    public let preferredPack: String
    /// Any of these package ids satisfies the requirement.
    public let acceptedPacks: [String]
    /// Profile name Offsend writes in `extends` (pack `install_as`).
    public let baseProfile: String

    public init(
        target: AIEditorHookTarget,
        preferredPack: String,
        acceptedPacks: [String],
        baseProfile: String
    ) {
        self.target = target
        self.preferredPack = preferredPack
        self.acceptedPacks = acceptedPacks
        self.baseProfile = baseProfile
    }

    public var pullHint: String {
        "nono pull \(preferredPack)"
    }

    /// Requirements for editors Offsend can wrap with nono.
    public static func forTarget(_ target: AIEditorHookTarget) -> NonoPackRequirement? {
        switch target {
        case .claude:
            return NonoPackRequirement(
                target: .claude,
                preferredPack: "nolabs-ai/claude",
                acceptedPacks: ["nolabs-ai/claude", "always-further/claude"],
                baseProfile: "claude-code"
            )
        case .codex:
            return NonoPackRequirement(
                target: .codex,
                preferredPack: "nolabs-ai/codex",
                acceptedPacks: ["nolabs-ai/codex", "always-further/codex"],
                baseProfile: "codex"
            )
        case .cursor, .windsurf:
            return nil
        }
    }

    /// Same string Offsend writes into generated profiles as `extends`.
    public static func baseProfile(for target: AIEditorHookTarget) -> String {
        forTarget(target)?.baseProfile ?? "default"
    }
}

/// Result of checking whether a registry pack (or its base profile) is present.
public struct NonoPackProbeResult: Equatable, Sendable {
    public let requirement: NonoPackRequirement
    /// Which accepted pack id was found, if any.
    public let installedPack: String?
    /// True when `~/.config/nono/profiles/<base>.json` (or equivalent) exists.
    public let baseProfilePresent: Bool

    public init(
        requirement: NonoPackRequirement,
        installedPack: String?,
        baseProfilePresent: Bool
    ) {
        self.requirement = requirement
        self.installedPack = installedPack
        self.baseProfilePresent = baseProfilePresent
    }

    public var isSatisfied: Bool {
        installedPack != nil || baseProfilePresent
    }

    public var missingMessage: String {
        "nono pack for \(requirement.target.rawValue) is not installed "
            + "(need profile `\(requirement.baseProfile)` from the registry). "
            + "Run: \(requirement.pullHint) "
            + "— see https://nono.sh/registry"
    }
}

/// Locates installed nono registry packs without requiring a network call.
public struct NonoPackProbe: Sendable {
    private let fileManager: FileManager
    private let configHome: URL

    public init(
        fileManager: FileManager = .default,
        configHome: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        if let configHome {
            self.configHome = configHome
        } else if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            self.configHome = URL(fileURLWithPath: xdg)
        } else {
            let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 }
                ?? fileManager.homeDirectoryForCurrentUser.path
            self.configHome = URL(fileURLWithPath: home).appendingPathComponent(".config")
        }
    }

    public var nonoConfigDirectory: URL {
        configHome.appendingPathComponent("nono")
    }

    public func probe(target: AIEditorHookTarget) -> NonoPackProbeResult? {
        guard let requirement = NonoPackRequirement.forTarget(target) else { return nil }
        return probe(requirement)
    }

    public func probe(_ requirement: NonoPackRequirement) -> NonoPackProbeResult {
        let installed = installedPack(matching: requirement.acceptedPacks)
        let profilePresent = baseProfilePresent(requirement.baseProfile)
        return NonoPackProbeResult(
            requirement: requirement,
            installedPack: installed,
            baseProfilePresent: profilePresent
        )
    }

    /// Probes every nono-wrappable target in `targets`.
    public func probe(targets: [AIEditorHookTarget]) -> [NonoPackProbeResult] {
        targets.compactMap { probe(target: $0) }
    }

    // MARK: - Detection

    private func installedPack(matching accepted: [String]) -> String? {
        let packagesRoot = nonoConfigDirectory.appendingPathComponent("packages")
        for pack in accepted {
            let parts = pack.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let dir = packagesRoot
                .appendingPathComponent(parts[0])
                .appendingPathComponent(parts[1])
            if directoryExists(dir) {
                return pack
            }
        }

        // Lockfile from `nono list --installed --json` / local store.
        if let fromLockfile = installedPackFromLockfile(matching: accepted) {
            return fromLockfile
        }
        return nil
    }

    private func installedPackFromLockfile(matching accepted: [String]) -> String? {
        let candidates = [
            nonoConfigDirectory.appendingPathComponent("packages-lock.json"),
            nonoConfigDirectory.appendingPathComponent("lockfile.json"),
            nonoConfigDirectory.appendingPathComponent("packages").appendingPathComponent("lockfile.json"),
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let packages = object["packages"] as? [String: Any] else {
                continue
            }
            for pack in accepted where packages[pack] != nil {
                return pack
            }
        }
        return nil
    }

    private func baseProfilePresent(_ name: String) -> Bool {
        let profiles = nonoConfigDirectory.appendingPathComponent("profiles")
        let candidates = [
            profiles.appendingPathComponent("\(name).json"),
            profiles.appendingPathComponent("\(name).profile.json"),
        ]
        return candidates.contains { fileManager.fileExists(atPath: $0.path) }
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
