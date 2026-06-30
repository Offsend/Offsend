import XCTest
@testable import OffsendScanAPI

final class ReportStorageTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = TestSupport.temporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testStoreAndLoadHTML() async throws {
        let storage = LocalReportStorage(directory: directory)
        let html = "<html><body>report</body></html>"
        let key = try await storage.storeHTML(jobID: "job-1", html: html)
        XCTAssertTrue(key.hasSuffix("job-1.html"))

        let loaded = try await storage.loadHTML(jobID: "job-1")
        XCTAssertEqual(loaded, html)
    }

    func testLoadReturnsNilForMissingFile() async throws {
        let storage = LocalReportStorage(directory: directory)
        let loaded = try await storage.loadHTML(jobID: "missing")
        XCTAssertNil(loaded)
    }

    func testStoreOverwritesExistingReport() async throws {
        let storage = LocalReportStorage(directory: directory)
        _ = try await storage.storeHTML(jobID: "job-1", html: "v1")
        _ = try await storage.storeHTML(jobID: "job-1", html: "v2")
        let loaded = try await storage.loadHTML(jobID: "job-1")
        XCTAssertEqual(loaded, "v2")
    }

    func testReportStorageBoxForwardsCalls() async throws {
        let storage = LocalReportStorage(directory: directory)
        let box = ReportStorageBox(storage)
        _ = try await box.storeHTML(jobID: "job-1", html: "boxed")
        let loaded = try await box.loadHTML(jobID: "job-1")
        XCTAssertEqual(loaded, "boxed")
    }

    func testCreatesDirectoryOnStore() async throws {
        let nested = directory.appendingPathComponent("nested/reports", isDirectory: true)
        let storage = LocalReportStorage(directory: nested)
        _ = try await storage.storeHTML(jobID: "job-1", html: "content")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
