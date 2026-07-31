#if os(macOS)
import Foundation

public enum CLIPathInstallationState: String, Sendable, Equatable {
    case installed
    case notInstalled
    case availableViaHomebrew
    case availableViaForeign
    case targetBlocked
    case brokenManagedLink
}

public struct CLIPathInstallationStatus: Sendable, Equatable {
    public let state: CLIPathInstallationState
    public let commandPath: String?
    public let commandTargetPath: String?
    /// App-managed symlink at `installPath` when another `offsend` resolves first in PATH.
    public let shadowingManagedInstallPath: String?
    public let installPath: String
    public let bundledCLIPath: String

    public init(
        state: CLIPathInstallationState,
        commandPath: String?,
        commandTargetPath: String?,
        shadowingManagedInstallPath: String? = nil,
        installPath: String,
        bundledCLIPath: String
    ) {
        self.state = state
        self.commandPath = commandPath
        self.commandTargetPath = commandTargetPath
        self.shadowingManagedInstallPath = shadowingManagedInstallPath
        self.installPath = installPath
        self.bundledCLIPath = bundledCLIPath
    }
}

public enum CLIPathInstallerError: Error, Equatable, Sendable {
    case bundledCLINotExecutable(path: String)
    case commandAlreadyAvailable(path: String)
    case installPathBlocked(path: String)
    case privilegedHelperFailed(message: String)
}

public struct CLIPathInstaller {
    public typealias PrivilegedShellRunner = @Sendable (String) throws -> Void

    public static let defaultInstallPath = "/usr/local/bin/offsend"
    public static let defaultPrivilegedShellRunner: PrivilegedShellRunner = { script in
        try CLIPathInstaller.runWithAdministratorPrivileges(script: script)
    }

    private let bundledCLIPath: String
    private let installPath: String
    private let searchPaths: [String]
    private let fileManager: FileManager
    private let runPrivilegedShell: PrivilegedShellRunner

    public init(
        bundledCLIPath: String? = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/offsend")
            .path,
        installPath: String = Self.defaultInstallPath,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        includeDefaultSearchPaths: Bool = true,
        fileManager: FileManager = .default,
        runPrivilegedShell: @escaping PrivilegedShellRunner = Self.defaultPrivilegedShellRunner
    ) {
        self.bundledCLIPath = URL(fileURLWithPath: bundledCLIPath ?? "").standardizedFileURL.path
        self.installPath = URL(fileURLWithPath: installPath).standardizedFileURL.path
        self.searchPaths = Self.makeSearchPaths(
            pathEnvironment: pathEnvironment,
            includeDefaultSearchPaths: includeDefaultSearchPaths
        )
        self.fileManager = fileManager
        self.runPrivilegedShell = runPrivilegedShell
    }

    public func status() -> CLIPathInstallationStatus {
        let shadowingManagedInstall = shadowingManagedInstallPath(primaryCommandPath: firstCommandPath())

        if let commandPath = firstCommandPath() {
            let targetPath = resolvedTargetPath(for: commandPath)
            switch classification(for: commandPath) {
            case .bundled:
                return makeStatus(
                    .installed,
                    commandPath: commandPath,
                    commandTargetPath: targetPath,
                    shadowingManagedInstallPath: shadowingManagedInstall
                )
            case .homebrew:
                return makeStatus(
                    .availableViaHomebrew,
                    commandPath: commandPath,
                    commandTargetPath: targetPath,
                    shadowingManagedInstallPath: shadowingManagedInstall
                )
            case .foreign:
                return makeStatus(
                    .availableViaForeign,
                    commandPath: commandPath,
                    commandTargetPath: targetPath,
                    shadowingManagedInstallPath: shadowingManagedInstall
                )
            }
        }

        if isBrokenManagedSymlink(at: installPath) {
            return makeStatus(
                .brokenManagedLink,
                commandPath: nil,
                commandTargetPath: resolvedTargetPath(for: installPath),
                shadowingManagedInstallPath: shadowingManagedInstall
            )
        }

        if fileManager.fileExists(atPath: installPath) {
            return makeStatus(
                .targetBlocked,
                commandPath: installPath,
                commandTargetPath: resolvedTargetPath(for: installPath),
                shadowingManagedInstallPath: shadowingManagedInstall
            )
        }

        return makeStatus(.notInstalled, commandPath: nil, commandTargetPath: nil, shadowingManagedInstallPath: shadowingManagedInstall)
    }

    public func install() throws {
        guard fileManager.isExecutableFile(atPath: bundledCLIPath) else {
            throw CLIPathInstallerError.bundledCLINotExecutable(path: bundledCLIPath)
        }

        let currentStatus = status()
        switch currentStatus.state {
        case .installed:
            return
        case .notInstalled, .brokenManagedLink:
            break
        case .availableViaHomebrew, .availableViaForeign:
            throw CLIPathInstallerError.commandAlreadyAvailable(path: currentStatus.commandPath ?? "offsend")
        case .targetBlocked:
            throw CLIPathInstallerError.installPathBlocked(path: installPath)
        }

        let script = """
        set -e
        mkdir -p \(Self.shellQuote(URL(fileURLWithPath: installPath).deletingLastPathComponent().path))
        if [ -e \(Self.shellQuote(installPath)) ] || [ -L \(Self.shellQuote(installPath)) ]; then
          existing_target="$(readlink \(Self.shellQuote(installPath)) || true)"
          if [ "$existing_target" != \(Self.shellQuote(bundledCLIPath)) ]; then
            case "$existing_target" in
              *Offsend.app/Contents/Helpers/offsend) ;;
              *) exit 17 ;;
            esac
          fi
          rm -f \(Self.shellQuote(installPath))
        fi
        ln -s \(Self.shellQuote(bundledCLIPath)) \(Self.shellQuote(installPath))
        """

        do {
            try runPrivilegedShell(script)
        } catch let error as CLIPathInstallerError {
            throw error
        } catch {
            throw CLIPathInstallerError.privilegedHelperFailed(message: error.localizedDescription)
        }
    }

    public func uninstall() throws {
        guard classification(for: installPath) == .bundled || isBrokenManagedSymlink(at: installPath) else {
            throw CLIPathInstallerError.installPathBlocked(path: installPath)
        }

        let script = """
        set -e
        if [ -L \(Self.shellQuote(installPath)) ]; then
          existing_target="$(readlink \(Self.shellQuote(installPath)) || true)"
          case "$existing_target" in
            \(Self.shellQuote(bundledCLIPath))|*Offsend.app/Contents/Helpers/offsend)
              rm -f \(Self.shellQuote(installPath))
              ;;
            *)
              exit 17
              ;;
          esac
        else
          exit 17
        fi
        """

        do {
            try runPrivilegedShell(script)
        } catch let error as CLIPathInstallerError {
            throw error
        } catch {
            throw CLIPathInstallerError.privilegedHelperFailed(message: error.localizedDescription)
        }
    }

    static func makeSearchPaths(pathEnvironment: String?, includeDefaultSearchPaths: Bool = true) -> [String] {
        var paths = (pathEnvironment ?? "")
            .split(separator: ":")
            .map(String.init)
        if includeDefaultSearchPaths {
            paths.append(contentsOf: [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin"
            ])
        }

        var seen = Set<String>()
        return paths.compactMap { path in
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            guard !standardized.isEmpty, seen.insert(standardized).inserted else { return nil }
            return standardized
        }
    }

    static func isHomebrewCLIPath(_ path: String) -> Bool {
        path.contains("/Caskroom/offsend-cli/")
            || path.contains("/Homebrew/Caskroom/offsend-cli/")
    }

    static func shellQuote(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_./:-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private enum PathClassification {
        case bundled
        case homebrew
        case foreign
    }

    private func firstCommandPath() -> String? {
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent("offsend")
                .standardizedFileURL
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func classification(for path: String) -> PathClassification {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let targetPath = resolvedTargetPath(for: standardized)

        if targetPath == bundledCLIPath || standardized == bundledCLIPath {
            return .bundled
        }

        if Self.isHomebrewCLIPath(standardized) || Self.isHomebrewCLIPath(targetPath ?? "") {
            return .homebrew
        }

        return .foreign
    }

    private func isBrokenManagedSymlink(at path: String) -> Bool {
        guard let target = resolvedTargetPath(for: path) else { return false }
        return target.contains("Offsend.app/Contents/Helpers/offsend")
            && !fileManager.fileExists(atPath: target)
    }

    private func resolvedTargetPath(for path: String) -> String? {
        guard let target = try? fileManager.destinationOfSymbolicLink(atPath: path) else {
            return nil
        }

        if target.hasPrefix("/") {
            return URL(fileURLWithPath: target).standardizedFileURL.path
        }

        return URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .appendingPathComponent(target)
            .standardizedFileURL
            .path
    }

    private func shadowingManagedInstallPath(primaryCommandPath: String?) -> String? {
        guard fileManager.fileExists(atPath: installPath) else { return nil }
        guard classification(for: installPath) == .bundled || isBrokenManagedSymlink(at: installPath) else {
            return nil
        }
        guard primaryCommandPath != installPath else { return nil }
        return installPath
    }

    private func makeStatus(
        _ state: CLIPathInstallationState,
        commandPath: String?,
        commandTargetPath: String?,
        shadowingManagedInstallPath: String? = nil
    ) -> CLIPathInstallationStatus {
        CLIPathInstallationStatus(
            state: state,
            commandPath: commandPath,
            commandTargetPath: commandTargetPath,
            shadowingManagedInstallPath: shadowingManagedInstallPath,
            installPath: installPath,
            bundledCLIPath: bundledCLIPath
        )
    }

    private static func runWithAdministratorPrivileges(script: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(appleScriptStringLiteral(script)) with administrator privileges"
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw CLIPathInstallerError.privilegedHelperFailed(message: error.localizedDescription)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIPathInstallerError.privilegedHelperFailed(
                message: message?.isEmpty == false ? message! : "Administrator authorization failed."
            )
        }
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            + "\""
    }
}
#endif
