import ArgumentParser
import Foundation
import MaskingCore
import OffsendRuntime

/// Shared validation helpers for CLI options. Invalid values terminate the
/// process with `OffsendExitCode.error` instead of being silently defaulted.
enum CLIParse {
    static func sealKey(key: String?, keyFile: String?) -> Data {
        do {
            return try SealKeyResolver.resolve(key: key, keyFilePath: keyFile).data
        } catch let error as SealError {
            CLIError.exit(.error, message: error.localizedDescription)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }
    }

    static func maxPlaintextBytes(_ value: Int?) -> Int {
        guard let value else { return SealEngine.defaultMaxPlaintextBytes }
        guard value > 0 else {
            CLIError.exit(.error, message: "--max-plaintext-bytes must be a positive integer.")
        }
        return value
    }

    static func outputFormat(_ rawValue: String) -> CheckOutputFormat {
        guard let format = CheckOutputFormat(rawValue: rawValue) else {
            CLIError.exit(.error, message: "Invalid --format value: \(rawValue). Expected one of: \(allValues(CheckOutputFormat.self)).")
        }
        return format
    }

    static func failPolicy(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        guard CheckFailPolicy(rawValue: rawValue) != nil else {
            CLIError.exit(.error, message: "Invalid --fail-on value: \(rawValue). Expected one of: \(allValues(CheckFailPolicy.self)).")
        }
        return rawValue
    }

    static func hookType(_ rawValue: String) -> HookType {
        guard let hookType = HookType(rawValue: rawValue) else {
            CLIError.exit(.error, message: "Invalid --type value: \(rawValue). Expected one of: \(allValues(HookType.self)).")
        }
        return hookType
    }

    static func projectConfig(from directory: URL) -> OffsendProjectConfig? {
        do {
            return try ProjectConfigLoader().load(from: directory)
        } catch let error as ProjectConfigLoaderError {
            CLIError.exit(.error, message: message(for: error))
        } catch {
            CLIError.exit(
                .error,
                message: "Failed to load \(ProjectConfigLoader.filename): \(error.localizedDescription)"
            )
        }
    }

    private static func message(for error: ProjectConfigLoaderError) -> String {
        switch error {
        case .unreadable(let path):
            return "Could not read project config at \(path)."
        case .invalidYAML(let path, let message):
            return "Invalid \(ProjectConfigLoader.filename) at \(path): \(message)"
        case .unsupportedVersion(let version):
            return "Unsupported \(ProjectConfigLoader.filename) version \(version). Expected version 1."
        }
    }

    private static func allValues<T: RawRepresentable & CaseIterable>(_ type: T.Type) -> String where T.RawValue == String {
        type.allCases.map(\.rawValue).joined(separator: ", ")
    }
}
