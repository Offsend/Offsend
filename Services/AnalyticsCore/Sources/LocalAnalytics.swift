import DetectionCore
import Foundation
import StorageCore

public protocol LocalAnalyticsRecording {
    func record(_ type: String, riskLevel: RiskLevel?, metadata: [String: String])
}

public extension LocalAnalyticsRecording {
    func record(_ type: String) {
        record(type, riskLevel: nil, metadata: [:])
    }

    func record(_ type: String, riskLevel: RiskLevel?) {
        record(type, riskLevel: riskLevel, metadata: [:])
    }
}

public final class LocalAnalytics: LocalAnalyticsRecording {
    private let store: LocalStoring

    public init(store: LocalStoring) {
        self.store = store
    }

    public func record(_ type: String, riskLevel: RiskLevel? = nil, metadata: [String: String] = [:]) {
        do {
            try store.appendEvent(LocalEvent(type: type, riskLevel: riskLevel, metadata: metadata))
        } catch {
            // Analytics is local-only and must never break Safe Paste.
        }
    }
}
