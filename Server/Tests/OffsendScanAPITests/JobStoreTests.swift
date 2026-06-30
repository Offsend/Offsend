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
}
