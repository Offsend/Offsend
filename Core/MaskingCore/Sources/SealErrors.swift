import Foundation

public enum SealError: Error, Equatable, LocalizedError, Sendable {
    case plaintextTooLarge(byteCount: Int, limit: Int)
    case invalidTokenFormat
    case unsupportedTokenVersion(String)
    case decryptionFailed
    case encryptionFailed
    case invalidKey(String)

    public var errorDescription: String? {
        switch self {
        case .plaintextTooLarge(let byteCount, let limit):
            return "Plaintext is \(byteCount) bytes; seal limit is \(limit) bytes."
        case .invalidTokenFormat:
            return "Invalid seal token format."
        case .unsupportedTokenVersion(let version):
            return "Unsupported seal token version: \(version)."
        case .decryptionFailed:
            return "Failed to decrypt seal token (wrong key or tampered token)."
        case .encryptionFailed:
            return "Failed to encrypt seal token."
        case .invalidKey(let reason):
            return "Invalid seal key: \(reason)"
        }
    }
}
