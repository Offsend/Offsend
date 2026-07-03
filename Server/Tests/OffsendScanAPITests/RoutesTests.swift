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
                XCTAssertTrue(body.contains("See what AI can read while you build | Offsend Check"))
                XCTAssertTrue(body.contains("name=\"description\""))
                XCTAssertTrue(body.contains("rel=\"canonical\""))
                XCTAssertTrue(body.contains("property=\"og:title\""))
                XCTAssertTrue(body.contains("application/ld+json"))
                XCTAssertTrue(body.contains("See what AI can read"))
                XCTAssertTrue(body.contains("/assets/landing.js"))
                XCTAssertTrue(body.contains("topnav"))
                XCTAssertTrue(body.contains("/assets/site.css"))
            }
        }
    }

    func testRobotsTxtDisallowsScanAndReportPaths() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/robots.txt", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "text/plain; charset=utf-8")
                let body = String(buffer: response.body)
                XCTAssertTrue(body.contains("Disallow: /r/"))
                XCTAssertTrue(body.contains("Disallow: /scan/"))
            }
        }
    }

    func testStaticAssetsServeCSS() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/assets/site.css", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "text/css; charset=utf-8")
                let body = String(buffer: response.body)
                XCTAssertTrue(body.contains("--brand-blue"))
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
                XCTAssertTrue(body.contains("data-job-id=\"job-abc\""))
                XCTAssertTrue(body.contains("Scanning…"))
                XCTAssertTrue(body.contains("noindex, nofollow"))
            }
        }
    }

    #if DEBUG
    func testPollingPreviewPageReturnsHTML() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/scan/page", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "text/html; charset=utf-8")
                let body = String(buffer: response.body)
                XCTAssertTrue(body.contains("Scanning…"))
                XCTAssertTrue(body.contains("data-debug=\"1\""))
                XCTAssertTrue(body.contains("/assets/polling.js"))
            }
        }
    }
    #endif

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

    func testCreateScanReturns429WhenRateLimited() async throws {
        let app = makeApp(rateLimiter: ScanRateLimiter(maxRequestsPerWindow: 1))
        try await app.test(.router) { client in
            let body = ByteBuffer(string: #"{"url":"https://github.com/offsend/macos"}"#)
            try await client.execute(
                uri: "/scan",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                XCTAssertEqual(response.status, .accepted)
            }
            try await client.execute(
                uri: "/scan",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                XCTAssertEqual(response.status, .tooManyRequests)
            }
        }
    }

    func testReportFallsBackToStorageWhenJobRecordMissing() async throws {
        // Simulates a server restart: the in-memory job record is gone but the
        // stored HTML still exists.
        let storage = LocalReportStorage(directory: reportDirectory)
        _ = try await storage.storeHTML(jobID: "job-1", html: "<html>persisted</html>")
        let app = makeApp(storage: storage)

        try await app.test(.router) { client in
            try await client.execute(uri: "/r/job-1", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(String(buffer: response.body), "<html>persisted</html>")
            }
        }
    }

    func testReportRejectsJobIDWithUnsafeCharacters() async throws {
        let storage = LocalReportStorage(directory: reportDirectory)
        _ = try await storage.storeHTML(jobID: "job-1", html: "<html>persisted</html>")
        let app = makeApp(storage: storage)

        try await app.test(.router) { client in
            for uri in ["/r/..%2Fjob-1", "/r/job.1", "/scan/%3Cscript%3E/page"] {
                try await client.execute(uri: uri, method: .get) { response in
                    XCTAssertEqual(response.status, .notFound, "expected 404 for \(uri)")
                }
            }
        }
    }

    func testCreateScanReusesInFlightJobForSameRepo() async throws {
        let tracker = JobPushTracker()
        let jobStore = JobStore(ttl: .seconds(3600))
        let app = makeApp(jobStore: jobStore, tracker: tracker, scanReuseWindow: .seconds(900))

        try await app.test(.router) { client in
            let body = ByteBuffer(string: #"{"url":"https://github.com/offsend/macos"}"#)
            var firstJobID = ""
            try await client.execute(
                uri: "/scan",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                let payload = try JSONDecoder().decode(CreateScanResponse.self, from: Data(buffer: response.body))
                firstJobID = payload.jobID
            }
            try await client.execute(
                uri: "/scan",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                let payload = try JSONDecoder().decode(CreateScanResponse.self, from: Data(buffer: response.body))
                XCTAssertEqual(payload.jobID, firstJobID)
            }
        }

        let pushed = await tracker.jobs
        XCTAssertEqual(pushed.count, 1)
    }

    func testCreateScanQueuesNewJobForDifferentRepo() async throws {
        let tracker = JobPushTracker()
        let app = makeApp(tracker: tracker, scanReuseWindow: .seconds(900))

        try await app.test(.router) { client in
            for repo in ["https://github.com/offsend/macos", "https://github.com/offsend/other"] {
                let body = ByteBuffer(string: "{\"url\":\"\(repo)\"}")
                try await client.execute(
                    uri: "/scan",
                    method: .post,
                    headers: [.contentType: "application/json"],
                    body: body
                ) { response in
                    XCTAssertEqual(response.status, .accepted)
                }
            }
        }

        let pushed = await tracker.jobs
        XCTAssertEqual(pushed.count, 2)
    }

    func testResponsesIncludeSecurityHeaders() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                XCTAssertNotNil(response.headers[.init("Content-Security-Policy")!])
                XCTAssertEqual(response.headers[.init("X-Content-Type-Options")!], "nosniff")
                XCTAssertEqual(response.headers[.init("X-Frame-Options")!], "DENY")
                XCTAssertNotNil(response.headers[.init("Referrer-Policy")!])
            }
        }
    }

    private func makeApp(
        jobStore: JobStore = JobStore(ttl: .seconds(3600)),
        tracker: JobPushTracker? = nil,
        storage: LocalReportStorage? = nil,
        rateLimiter: ScanRateLimiter = ScanRateLimiter(maxRequestsPerWindow: 1000),
        scanReuseWindow: Duration = .seconds(0)
    ) -> Application<Router<AppRequestContext>.Responder> {
        let storage = storage ?? LocalReportStorage(directory: reportDirectory)
        let config = TestSupport.makeConfiguration(
            reportDirectory: reportDirectory,
            scanReuseWindow: scanReuseWindow
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
            rateLimiter: rateLimiter,
            pushScanJob: pushScanJob
        )
        return TestSupport.makeTestApplication(dependencies: dependencies)
    }
}
