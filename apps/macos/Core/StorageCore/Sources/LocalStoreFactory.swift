import Foundation
import MaskingCore

public enum LocalStoreFactory {
    public static func makeDefaultStore(maskingEngine: TextMasking) throws -> any LocalStoring {
        #if canImport(Security)
        return try SecureLocalStore(maskingEngine: maskingEngine)
        #else
        return try FileLocalStore()
        #endif
    }
}
