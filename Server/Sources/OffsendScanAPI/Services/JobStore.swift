import Foundation

actor JobStore {
    private var jobs: [String: ScanJobRecord] = [:]
    private let ttl: Duration
    /// When set, every record is mirrored to `<directory>/<id>.json` so job
    /// state (and report links) survive server restarts.
    private let directory: URL?

    init(ttl: Duration, directory: URL? = nil) {
        self.ttl = ttl
        self.directory = directory
        if let directory {
            let cutoff = Date().addingTimeInterval(-TimeInterval(ttl.components.seconds))
            self.jobs = Self.loadPersistedRecords(from: directory, cutoff: cutoff)
        }
    }

    func create(id: String, repoURL: String) -> ScanJobRecord {
        let now = Date()
        let record = ScanJobRecord(
            id: id,
            repoURL: repoURL,
            status: .queued,
            createdAt: now,
            updatedAt: now,
            reportJSON: nil,
            reportHTMLKey: nil,
            errorMessage: nil
        )
        jobs[id] = record
        persist(record)
        return record
    }

    func get(_ id: String) -> ScanJobRecord? {
        guard let record = jobs[id] else { return nil }
        guard record.updatedAt >= expiryCutoff() else {
            remove(id)
            return nil
        }
        return record
    }

    /// Jobs waiting for or occupying a worker; used to cap total queue depth.
    func pendingCount() -> Int {
        let cutoff = expiryCutoff()
        return jobs.values.count {
            ($0.status == .queued || $0.status == .running) && $0.updatedAt >= cutoff
        }
    }

    /// A job for the same repository that a new scan request can reuse:
    /// one still in flight, or one completed recently enough to serve as a cache.
    func reusableJob(repoURL: String, completedWithin window: Duration) -> ScanJobRecord? {
        let expiry = expiryCutoff()
        let completedCutoff = Date().addingTimeInterval(-TimeInterval(window.components.seconds))
        return jobs.values
            .filter { record in
                guard record.repoURL == repoURL, record.updatedAt >= expiry else { return false }
                switch record.status {
                case .queued, .running:
                    return true
                case .completed:
                    return record.createdAt >= completedCutoff
                case .failed:
                    return false
                }
            }
            .max { $0.createdAt < $1.createdAt }
    }

    func markRunning(_ id: String) {
        guard var record = jobs[id] else { return }
        record.status = .running
        record.updatedAt = Date()
        jobs[id] = record
        persist(record)
    }

    func markCompleted(_ id: String, reportJSON: String, reportHTMLKey: String) {
        guard var record = jobs[id] else { return }
        record.status = .completed
        record.updatedAt = Date()
        record.reportJSON = reportJSON
        record.reportHTMLKey = reportHTMLKey
        record.errorMessage = nil
        jobs[id] = record
        persist(record)
    }

    func markFailed(_ id: String, message: String) {
        guard var record = jobs[id] else { return }
        record.status = .failed
        record.updatedAt = Date()
        record.errorMessage = message
        jobs[id] = record
        persist(record)
    }

    /// Full sweep; called periodically by the maintenance service rather than
    /// on every request.
    func purgeExpired() {
        let cutoff = expiryCutoff()
        for (id, record) in jobs where record.updatedAt < cutoff {
            remove(id)
        }
    }

    private func expiryCutoff() -> Date {
        Date().addingTimeInterval(-TimeInterval(ttl.components.seconds))
    }

    private func remove(_ id: String) {
        jobs[id] = nil
        if let fileURL = persistenceURL(for: id) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Persistence

    private func persistenceURL(for id: String) -> URL? {
        directory?.appendingPathComponent("\(id).json")
    }

    private func persist(_ record: ScanJobRecord) {
        guard let directory else { return }
        Self.persist(record, in: directory)
    }

    private static func persist(_ record: ScanJobRecord, in directory: URL) {
        let fileURL = directory.appendingPathComponent("\(record.id).json")
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func loadPersistedRecords(from directory: URL, cutoff: Date) -> [String: ScanJobRecord] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [:] }

        var records: [String: ScanJobRecord] = [:]
        let decoder = JSONDecoder()
        for fileURL in files where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  var record = try? decoder.decode(ScanJobRecord.self, from: data) else {
                try? FileManager.default.removeItem(at: fileURL)
                continue
            }
            guard record.updatedAt >= cutoff else {
                try? FileManager.default.removeItem(at: fileURL)
                continue
            }
            // In-flight jobs died with the previous process; the queue that held
            // them is gone, so they would otherwise stay pending forever.
            if record.status == .queued || record.status == .running {
                record.status = .failed
                record.updatedAt = Date()
                record.errorMessage = "Scan was interrupted by a server restart. Please retry."
                persist(record, in: directory)
            }
            records[record.id] = record
        }
        return records
    }
}
