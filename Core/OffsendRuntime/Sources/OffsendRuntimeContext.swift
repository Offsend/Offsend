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

    public static func load(store: LocalStoring = try! SecureLocalStore()) throws -> OffsendRuntimeContext {
        OffsendRuntimeContext(
            settings: try store.loadSettings(),
            customDictionaries: try store.loadCustomDictionaries()
        )
    }
}
