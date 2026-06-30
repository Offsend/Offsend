import Foundation

actor JobStore {
    private var jobs: [String: ScanJobRecord] = [:]
    private let ttl: Duration

    init(ttl: Duration) {
        self.ttl = ttl
    }

    func create(id: String, repoURL: String) -> ScanJobRecord {
        purgeExpired()
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
        return record
    }

    func get(_ id: String) -> ScanJobRecord? {
        purgeExpired()
        return jobs[id]
    }

    func markRunning(_ id: String) {
        guard var record = jobs[id] else { return }
        record.status = .running
        record.updatedAt = Date()
        jobs[id] = record
    }

    func markCompleted(_ id: String, reportJSON: String, reportHTMLKey: String) {
        guard var record = jobs[id] else { return }
        record.status = .completed
        record.updatedAt = Date()
        record.reportJSON = reportJSON
        record.reportHTMLKey = reportHTMLKey
        record.errorMessage = nil
        jobs[id] = record
    }

    func markFailed(_ id: String, message: String) {
        guard var record = jobs[id] else { return }
        record.status = .failed
        record.updatedAt = Date()
        record.errorMessage = message
        jobs[id] = record
    }

    private func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-TimeInterval(ttl.components.seconds))
        jobs = jobs.filter { $0.value.updatedAt >= cutoff }
    }
}
