#if canImport(Security)
import Foundation

public enum StorageCoreStrings: Sendable {
    public static func storageErrorKeyGenerationFailed(_ status: OSStatus) -> String {
        "Failed to generate encryption key: \(status)"
    }

    public static func storageErrorKeychainReadFailed(_ status: OSStatus) -> String {
        "Failed to read encryption key from Keychain: \(status)"
    }

    public static func storageErrorKeychainWriteFailed(_ status: OSStatus) -> String {
        "Failed to store encryption key in Keychain: \(status)"
    }
}
#endif
