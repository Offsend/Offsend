import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import XCTest
@testable import OffsendScanAPI

final class RoutesTests: XCTestCase {
    private var reportDirectory: URL!
    private var htmlTemplates: HTMLTemplateRenderer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        reportDirectory = TestSupport.temporaryDirectory()
        htmlTemplates = try HTMLTemplateRenderer.load()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: reportDirectory)
        super.tearDown()
    }

    func testHealthReturnsOk() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(String(buffer: response.body), "ok")
            }
        }
    }

    func testLandingPageReturnsHTML() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "text/html; charset=utf-8")
                let body = String(buffer: response.body)
                XCTAssertTrue(body.contains("Scan a public repository"))
                XCTAssertTrue(body.contains("fetch('/scan'"))
            }
        }
    }

    func testCreateScanAcceptsValidRequest() async throws {
        let tracker = JobPushTracker()
        let jobStore = JobStore(ttl: .seconds(3600))
        let app = makeApp(jobStore: jobStore, tracker: tracker)

        try await app.test(.router) { client in
            let body = ByteBuffer(string: #"{"url":"https://github.com/offsend/macos"}"#)
            try await client.execute(
                uri: "/scan",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                XCTAssertEqual(response.headers[.contentType], "application/json")
                XCTAssertNotNil(response.headers[.location])

                let payload = try JSONDecoder().decode(CreateScanResponse.self, from: Data(buffer: response.body))
                XCTAssertFalse(payload.jobID.isEmpty)
                XCTAssertEqual(payload.statusURL, "/scan/\(payload.jobID)")
                XCTAssertEqual(payload.reportURL, "/r/\(payload.jobID)")
                XCTAssertEqual(payload.pollIntervalMs, 2000)
            }
        }

        let pushed = await tracker.jobs
        XCTAssertEqual(pushed.count, 1)
        XCTAssertEqual(pushed[0].repoURL, "https://github.com/offsend/macos")

        let stored = await jobStore.get(pushed[0].jobID)
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored?.status, .queued)
    }

    func testCreateScanRejectsInvalidURL() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            let body = ByteBuffer(string: #"{"url":"https://example.com/a/b"}"#)
            try await client.execute(
                uri: "/scan",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                // RepositoryURLError is not HTTPResponseError; router test framework maps it to 500.
                XCTAssertEqual(response.status, .internalServerError)
            }
        }
    }

    func testGetScanStatusReturnsQueuedJob() async throws {
        let jobStore = JobStore(ttl: .seconds(3600))
        _ = await jobStore.create(id: "job-1", repoURL: "https://github.com/org/repo")
        let app = makeApp(jobStore: jobStore)

        try await app.test(.router) { client in
            try await client.execute(uri: "/scan/job-1", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try JSONDecoder().decode(ScanStatusResponse.self, from: Data(buffer: response.body))
                XCTAssertEqual(payload.jobID, "job-1")
                XCTAssertEqual(payload.status, .queued)
                XCTAssertEqual(payload.repoURL, "https://github.com/org/repo")
                XCTAssertNil(payload.reportURL)
                XCTAssertNil(payload.report)
            }
        }
    }

    func testGetScanStatusReturnsCompletedJobWithReport() async throws {
        let jobStore = JobStore(ttl: .seconds(3600))
        _ = await jobStore.create(id: "job-1", repoURL: "https://github.com/org/repo")
        let reportJSON = TestSupport.sampleReportJSON()
        await jobStore.markCompleted("job-1", reportJSON: reportJSON, reportHTMLKey: "reports/job-1.html")
        let app = makeApp(jobStore: jobStore)

        try await app.test(.router) { client in
            try await client.execute(uri: "/scan/job-1", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try JSONDecoder().decode(ScanStatusResponse.self, from: Data(buffer: response.body))
                XCTAssertEqual(payload.status, .completed)
                XCTAssertEqual(payload.reportURL, "/r/job-1")
                XCTAssertNotNil(payload.report)
                XCTAssertEqual(payload.report?.scanComplete, true)
            }
        }
    }

    func testGetScanStatusReturnsFailedJobWithError() async throws {
        let jobStore = JobStore(ttl: .seconds(3600))
        _ = await jobStore.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await jobStore.markFailed("job-1", message: "clone timed out")
        let app = makeApp(jobStore: jobStore)

        try await app.test(.router) { client in
            try await client.execute(uri: "/scan/job-1", method: .get) { response in
                let payload = try JSONDecoder().decode(ScanStatusResponse.self, from: Data(buffer: response.body))
                XCTAssertEqual(payload.status, .failed)
                XCTAssertEqual(payload.errorMessage, "clone timed out")
            }
        }
    }

    func testGetScanStatusReturns404ForMissingJob() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/scan/missing", method: .get) { response in
                XCTAssertEqual(response.status, .notFound)
            }
        }
    }

    func testPollingPageContainsJobID() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/scan/job-abc/page", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "text/html; charset=utf-8")
                let body = String(buffer: response.body)
                XCTAssertTrue(body.contains("job-abc"))
                XCTAssertTrue(body.contains("Scan in progress"))
            }
        }
    }

    func testReportReturnsHTMLForCompletedJob() async throws {
        let jobStore = JobStore(ttl: .seconds(3600))
        _ = await jobStore.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await jobStore.markCompleted("job-1", reportJSON: "{}", reportHTMLKey: "reports/job-1.html")

        let storage = LocalReportStorage(directory: reportDirectory)
        _ = try await storage.storeHTML(jobID: "job-1", html: "<html>report</html>")
        let app = makeApp(jobStore: jobStore, storage: storage)

        try await app.test(.router) { client in
            try await client.execute(uri: "/r/job-1", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "text/html; charset=utf-8")
                XCTAssertEqual(String(buffer: response.body), "<html>report</html>")
            }
        }
    }

    func testReportReturns409WhenJobNotCompleted() async throws {
        let jobStore = JobStore(ttl: .seconds(3600))
        _ = await jobStore.create(id: "job-1", repoURL: "https://github.com/org/repo")
        let app = makeApp(jobStore: jobStore)

        try await app.test(.router) { client in
            try await client.execute(uri: "/r/job-1", method: .get) { response in
                XCTAssertEqual(response.status, .conflict)
            }
        }
    }

    func testReportReturns404WhenHTMLMissing() async throws {
        let jobStore = JobStore(ttl: .seconds(3600))
        _ = await jobStore.create(id: "job-1", repoURL: "https://github.com/org/repo")
        await jobStore.markCompleted("job-1", reportJSON: "{}", reportHTMLKey: "reports/job-1.html")
        let app = makeApp(jobStore: jobStore)

        try await app.test(.router) { client in
            try await client.execute(uri: "/r/job-1", method: .get) { response in
                XCTAssertEqual(response.status, .notFound)
            }
        }
    }

    func testReportReturns404ForMissingJob() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/r/missing", method: .get) { response in
                XCTAssertEqual(response.status, .notFound)
            }
        }
    }

    private func makeApp(
        jobStore: JobStore = JobStore(ttl: .seconds(3600)),
        tracker: JobPushTracker? = nil,
        storage: LocalReportStorage? = nil
    ) -> Application<Router<AppRequestContext>.Responder> {
        let storage = storage ?? LocalReportStorage(directory: reportDirectory)
        let config = AppConfiguration(
            host: "127.0.0.1",
            port: 8080,
            gitPath: "/usr/bin/git",
            cloneTimeout: .seconds(120),
            scanWorkDirectory: reportDirectory.deletingLastPathComponent().appendingPathComponent("work", isDirectory: true),
            reportStorageDirectory: reportDirectory,
            reportTTL: .seconds(3600),
            jobWorkers: 1,
            valkeyHost: nil,
            valkeyPort: 6379,
            valkeyQueueName: "test",
            r2: nil,
            toolVersion: "test-1.0.0"
        )
        let pushScanJob: @Sendable (ScanRepositoryJobParameters) async throws -> Void = { parameters in
            if let tracker {
                await tracker.track(parameters)
            }
        }
        let dependencies = AppDependencies(
            config: config,
            jobStore: jobStore,
            reportStorage: ReportStorageBox(storage),
            htmlTemplates: htmlTemplates,
            pushScanJob: pushScanJob
        )
        return TestSupport.makeTestApplication(dependencies: dependencies)
    }
}
