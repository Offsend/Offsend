import DetectionCore
import Foundation
import StorageCore

public struct OffsendRuntimeContext: Sendable {
    public let settings: AppSettings
    public let customDictionaries: [CustomDictionaryItem]

    public init(
        settings: AppSettings,
        customDictionaries: [CustomDictionaryItem]
    ) {
        self.settings = settings
        self.customDictionaries = customDictionaries
    }

    public static func load(store: (any LocalStoring)? = nil) throws -> OffsendRuntimeContext {
        let resolvedStore = try store ?? LocalStoreFactory.makeDefaultStore()
        return OffsendRuntimeContext(
            settings: try resolvedStore.loadSettings(),
            customDictionaries: try resolvedStore.loadCustomDictionaries()
        )
    }
}
