import XCTest
@testable import OffsendScanAPI

final class JobStoreTests: XCTestCase {
    func testCreateReturnsQueuedRecord() async {
        let store = JobStore(ttl: .seconds(3600))
        let record = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        XCTAssertEqual(record.id, "job-1")
        XCTAssertEqual(record.repoURL, "https://github.com/org/repo")
        XCTAssertEqual(record.status, .queued)
        XCTAssertNil(record.reportJSON)
        XCTAssertNil(record.reportHTMLKey)
        XCTAssertNil(record.errorMessage)
    }

    func testGetReturnsCreatedRecord() async {
        let store = JobStore(ttl: .seconds(3600))
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        let fetched = await store.get("job-1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, "job-1")
    }

    func testGetReturnsNilForUnknownID() async {
        let store = JobStore(ttl: .seconds(3600))
        let fetched = await store.get("missing")
        XCTAssertNil(fetched)
    }

    func testMarkRunningUpdatesStatus() async {
        let store = JobStore(ttl: .seconds(3600))
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await store.markRunning("job-1")
        let record = await store.get("job-1")
        XCTAssertEqual(record?.status, .running)
    }

    func testMarkCompletedStoresReportAndClearsError() async {
        let store = JobStore(ttl: .seconds(3600))
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await store.markFailed("job-1", message: "temporary")
        await store.markCompleted("job-1", reportJSON: "{\"ok\":true}", reportHTMLKey: "reports/job-1.html")

        let record = await store.get("job-1")
        XCTAssertEqual(record?.status, .completed)
        XCTAssertEqual(record?.reportJSON, "{\"ok\":true}")
        XCTAssertEqual(record?.reportHTMLKey, "reports/job-1.html")
        XCTAssertNil(record?.errorMessage)
    }

    func testMarkFailedStoresErrorMessage() async {
        let store = JobStore(ttl: .seconds(3600))
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await store.markFailed("job-1", message: "clone failed")
        let record = await store.get("job-1")
        XCTAssertEqual(record?.status, .failed)
        XCTAssertEqual(record?.errorMessage, "clone failed")
    }

    func testMarkRunningIgnoresUnknownID() async {
        let store = JobStore(ttl: .seconds(3600))
        await store.markRunning("missing")
        let missingAfterRunning = await store.get("missing")
        XCTAssertNil(missingAfterRunning)
    }

    func testMarkCompletedIgnoresUnknownID() async {
        let store = JobStore(ttl: .seconds(3600))
        await store.markCompleted("missing", reportJSON: "{}", reportHTMLKey: "key")
        let missingAfterCompleted = await store.get("missing")
        XCTAssertNil(missingAfterCompleted)
    }

    func testMarkFailedIgnoresUnknownID() async {
        let store = JobStore(ttl: .seconds(3600))
        await store.markFailed("missing", message: "error")
        let missingAfterFailed = await store.get("missing")
        XCTAssertNil(missingAfterFailed)
    }

    func testPurgesExpiredRecords() async throws {
        let store = JobStore(ttl: .seconds(1))
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        try await Task.sleep(for: .milliseconds(1100))
        let fetched = await store.get("job-1")
        XCTAssertNil(fetched)
    }

    func testDoesNotPurgeFreshRecords() async {
        let store = JobStore(ttl: .seconds(3600))
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        let fetched = await store.get("job-1")
        XCTAssertNotNil(fetched)
    }

    func testReusableJobReturnsInFlightJob() async {
        let store = JobStore(ttl: .seconds(3600))
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        let reusable = await store.reusableJob(repoURL: "https://github.com/org/repo", completedWithin: .seconds(0))
        XCTAssertEqual(reusable?.id, "job-1")
    }

    func testReusableJobReturnsRecentlyCompletedJob() async {
        let store = JobStore(ttl: .seconds(3600))
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await store.markCompleted("job-1", reportJSON: "{}", reportHTMLKey: "key")
        let reusable = await store.reusableJob(repoURL: "https://github.com/org/repo", completedWithin: .seconds(900))
        XCTAssertEqual(reusable?.id, "job-1")
    }

    func testReusableJobIgnoresFailedAndStaleCompletedJobs() async {
        let store = JobStore(ttl: .seconds(3600))
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await store.markFailed("job-1", message: "boom")
        var reusable = await store.reusableJob(repoURL: "https://github.com/org/repo", completedWithin: .seconds(900))
        XCTAssertNil(reusable)

        _ = await store.create(id: "job-2", repoURL: "https://github.com/org/repo")
        await store.markCompleted("job-2", reportJSON: "{}", reportHTMLKey: "key")
        // Zero-width window: even a just-completed job is considered stale.
        reusable = await store.reusableJob(repoURL: "https://github.com/org/repo", completedWithin: .seconds(0))
        XCTAssertNil(reusable)
    }
}

final class JobStorePersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = TestSupport.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testCompletedRecordSurvivesRestart() async {
        let store = JobStore(ttl: .seconds(3600), directory: directory)
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await store.markCompleted("job-1", reportJSON: "{\"ok\":true}", reportHTMLKey: "reports/job-1.html")

        let restarted = JobStore(ttl: .seconds(3600), directory: directory)
        let record = await restarted.get("job-1")
        XCTAssertEqual(record?.status, .completed)
        XCTAssertEqual(record?.reportJSON, "{\"ok\":true}")
        XCTAssertEqual(record?.reportURL, "/r/job-1")
    }

    func testInFlightRecordBecomesFailedAfterRestart() async {
        let store = JobStore(ttl: .seconds(3600), directory: directory)
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await store.markRunning("job-1")

        let restarted = JobStore(ttl: .seconds(3600), directory: directory)
        let record = await restarted.get("job-1")
        XCTAssertEqual(record?.status, .failed)
        XCTAssertNotNil(record?.errorMessage)
        let pending = await restarted.pendingCount()
        XCTAssertEqual(pending, 0)
    }

    func testExpiredRecordIsDroppedOnRestart() async throws {
        let store = JobStore(ttl: .seconds(1), directory: directory)
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await store.markCompleted("job-1", reportJSON: "{}", reportHTMLKey: "key")
        try await Task.sleep(for: .milliseconds(1100))

        let restarted = JobStore(ttl: .seconds(1), directory: directory)
        let record = await restarted.get("job-1")
        XCTAssertNil(record)
    }

    func testPurgeExpiredRemovesPersistedFiles() async throws {
        let store = JobStore(ttl: .seconds(1), directory: directory)
        _ = await store.create(id: "job-1", repoURL: "https://github.com/org/repo")
        try await Task.sleep(for: .milliseconds(1100))
        await store.purgeExpired()

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.filter { $0.hasSuffix(".json") }.isEmpty)
    }
}
