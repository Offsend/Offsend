import Foundation
import StorageCore

/// On-device counters only — never transmitted.
public final class LocalAnalytics: @unchecked Sendable {
    private let store: LocalStoring

    public init(store: LocalStoring) {
        self.store = store
    }

    public func track(_ event: AnalyticsEvent) {
        do {
            try store.appendEvent(
                LocalEvent(type: event.name, riskLevel: event.riskLevel, metadata: event.metadata)
            )
        } catch {
            // Local analytics must never break Safe Paste.
        }
    }
}
