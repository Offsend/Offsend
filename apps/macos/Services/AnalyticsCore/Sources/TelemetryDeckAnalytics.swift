import Foundation
import TelemetryDeck

/// Anonymous product analytics via TelemetryDeck — user can disable in Settings.
public final class TelemetryDeckAnalytics: @unchecked Sendable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public func track(_ event: AnalyticsEvent) {
        guard isEnabled, TelemetryDeckBootstrap.isInitialized else { return }
        TelemetryDeck.signal(event.name, parameters: event.telemetryParameters)
    }
}
