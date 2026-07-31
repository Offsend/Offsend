import Foundation

/// Sliding-window per-client limiter for scan creation. Keys are client IPs
/// (taken from the proxy headers), values are recent request timestamps.
actor ScanRateLimiter {
    private let maxRequests: Int
    private let window: TimeInterval
    private var requests: [String: [Date]] = [:]

    init(maxRequestsPerWindow: Int, window: Duration = .seconds(60)) {
        self.maxRequests = maxRequestsPerWindow
        self.window = TimeInterval(window.components.seconds)
    }

    func allow(_ key: String, now: Date = Date()) -> Bool {
        let cutoff = now.addingTimeInterval(-window)
        if requests.count > 10_000 {
            requests = requests.filter { $0.value.contains { $0 >= cutoff } }
        }

        var timestamps = (requests[key] ?? []).filter { $0 >= cutoff }
        guard timestamps.count < maxRequests else {
            requests[key] = timestamps
            return false
        }
        timestamps.append(now)
        requests[key] = timestamps
        return true
    }
}
