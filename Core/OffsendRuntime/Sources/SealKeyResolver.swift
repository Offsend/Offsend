import Crypto
import Foundation
import MaskingCore

public enum SealKeyResolver {
    public static let environmentVariable = "OFFSEND_SEAL_KEY"
    public static let keyByteCount = 32

    /// Generates a fresh 32-byte AES-256 seal key.
    public static func generate() -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
    }

    public enum Source: Equatable, Sendable {
        case flagKey
        case keyFile
        case environment
    }

    public struct ResolvedKey: Equatable, Sendable {
        public let data: Data
        public let source: Source

        public init(data: Data, source: Source) {
            self.data = data
            self.source = source
        }
    }

    /// Resolves a 32-byte seal key. Priority: `key` > `keyFilePath` > `OFFSEND_SEAL_KEY`.
    public static func resolve(
        key: String?,
        keyFilePath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ResolvedKey {
        if key != nil, keyFilePath != nil {
            throw SealError.invalidKey("pass either --key or --key-file, not both")
        }

        if let key {
            return ResolvedKey(data: try decodeBase64Key(key), source: .flagKey)
        }

        if let keyFilePath {
            return ResolvedKey(data: try loadKeyFile(at: keyFilePath), source: .keyFile)
        }

        if let envValue = environment[environmentVariable], !envValue.isEmpty {
            return ResolvedKey(data: try decodeBase64Key(envValue), source: .environment)
        }

        throw SealError.invalidKey(
            "provide --key, --key-file, or set \(environmentVariable)"
        )
    }

    public static func decodeBase64Key(_ string: String) throws -> Data {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed) else {
            throw SealError.invalidKey("value is not valid base64")
        }
        guard data.count == 32 else {
            throw SealError.invalidKey("expected 32 bytes after base64 decode, got \(data.count)")
        }
        return data
    }

    public static func loadKeyFile(at path: String) throws -> Data {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SealError.invalidKey("could not read key file at \(path)")
        }

        if data.count == 32 {
            return data
        }

        if let asString = String(data: data, encoding: .utf8) {
            let trimmed = asString.trimmingCharacters(in: .whitespacesAndNewlines)
            if let decoded = try? decodeBase64Key(trimmed) {
                return decoded
            }
        }

        throw SealError.invalidKey(
            "key file must be 32 raw bytes or base64 encoding of 32 bytes"
        )
    }
}
