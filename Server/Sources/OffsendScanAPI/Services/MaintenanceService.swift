import Foundation
import Logging
import ServiceLifecycle

/// Periodic housekeeping: purges expired job records and deletes report HTML
/// files older than the report TTL so the data volume doesn't grow forever.
/// R2 objects are expected to be cleaned by a bucket lifecycle rule.
struct MaintenanceService: Service {
    let jobStore: JobStore
    let reportDirectory: URL
    let ttl: Duration
    var interval: Duration = .seconds(3600)
    let logger: Logger

    func run() async throws {
        try? await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                await jobStore.purgeExpired()
                cleanExpiredReports()
                try await Task.sleep(for: interval)
            }
        }
    }

    private func cleanExpiredReports() {
        let cutoff = Date().addingTimeInterval(-TimeInterval(ttl.components.seconds))
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: reportDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        var removed = 0
        for fileURL in files where fileURL.pathExtension == "html" {
            guard let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate else { continue }
            if modified < cutoff {
                try? fileManager.removeItem(at: fileURL)
                removed += 1
            }
        }
        if removed > 0 {
            logger.info("Removed expired reports", metadata: ["count": .string("\(removed)")])
        }
    }
}
