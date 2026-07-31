import Foundation
import TelemetryDeck

public enum TelemetryDeckBootstrap {
    public static let appIDInfoPlistKey = "TelemetryDeckAppID"

    public private(set) static var isInitialized = false

    /// Initializes TelemetryDeck when `TelemetryDeckAppID` is set in the app Info.plist.
    @discardableResult
    public static func initializeIfConfigured(bundle: Bundle = .main) -> Bool {
        guard !isInitialized else { return true }

        guard let appID = bundle.object(forInfoDictionaryKey: appIDInfoPlistKey) as? String,
              !appID.isEmpty
        else {
            return false
        }

        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        isInitialized = true
        return true
    }
}
