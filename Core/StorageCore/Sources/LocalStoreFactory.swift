import Foundation

public enum LocalStoreFactory {
    public static func makeDefaultStore() throws -> any LocalStoring {
        #if canImport(Security)
        return try SecureLocalStore()
        #else
        return try FileLocalStore()
        #endif
    }
}
