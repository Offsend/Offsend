import Foundation

public struct LicensePricingCachedEnvelope: Codable, Equatable, Sendable {
    var fetchedAt: Date
    var ttlSeconds: Int
    var catalog: LicensePricingCatalog
}

/// Persists last successful `/pricing` response for offline and error fallback (may be past TTL).
public final class LicensePricingCacheStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base.appendingPathComponent("Offsend", isDirectory: true)
                .appendingPathComponent("pricing_cache.json", isDirectory: false)
        }
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> LicensePricingCachedEnvelope? {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(LicensePricingCachedEnvelope.self, from: data)
    }

    public func save(_ envelope: LicensePricingCachedEnvelope) throws {
        lock.lock()
        defer { lock.unlock() }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL, options: [.atomic])
    }
}
