import Foundation

/// Routes each event to local on-device storage and optional TelemetryDeck product analytics.
public final class AppAnalytics: @unchecked Sendable {
    public let local: LocalAnalytics
    public let product: TelemetryDeckAnalytics

    public init(local: LocalAnalytics, product: TelemetryDeckAnalytics) {
        self.local = local
        self.product = product
    }

    public func track(_ event: AnalyticsEvent) {
        local.track(event)
        product.track(event)
    }

    public func setProductAnalyticsEnabled(_ enabled: Bool) {
        product.isEnabled = enabled
    }
}
