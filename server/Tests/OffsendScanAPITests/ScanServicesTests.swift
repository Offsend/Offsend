import Foundation
import Logging
import XCTest
@testable import OffsendScanAPI

final class RepositoryScannerTests: XCTestCase {
    private var fixtureDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureDirectory = TestSupport.temporaryDirectory()
        try createFixture()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fixtureDirectory)
        super.tearDown()
    }

    func testScanDetectsExposedSensitiveFiles() throws {
        let scanner = RepositoryScanner()
        let report = try scanner.scan(directoryURL: fixtureDirectory, toolVersion: "test-1.0.0")
        let object = try JSONSerialization.jsonObject(with: Data(report.json.utf8)) as! [String: Any]
        XCTAssertEqual(object["scanComplete"] as? Bool, true)
        let exposed = object["exposedPatterns"] as? [[String: Any]]
        XCTAssertFalse(exposed?.isEmpty ?? true)
        let totals = object["totals"] as? [String: Any]
        XCTAssertGreaterThan(totals?["exposedFiles"] as? Int ?? 0, 0)
    }

    func testRenderJSONProducesValidReportDocument() throws {
        let scanner = RepositoryScanner()
        let report = try scanner.scan(directoryURL: fixtureDirectory, toolVersion: "test-2.0.0")
        let object = try JSONSerialization.jsonObject(with: Data(report.json.utf8)) as! [String: Any]
        XCTAssertEqual(object["toolVersion"] as? String, "test-2.0.0")
        XCTAssertEqual(object["scanComplete"] as? Bool, true)
        XCTAssertNotNil(object["exposedPatterns"])
        XCTAssertNotNil(object["ignoreFilesPresent"])
        XCTAssertNotNil(object["rules"])
        XCTAssertNotNil(object["fixFiles"])
    }

    func testScanTreatsOffsendManagedIgnoreFilesAsPresent() throws {
        // `.offsend.yml` with `ignore.commit: false` keeps AI ignore files out of
        // git, so their absence from a clone is expected — not a missing protection.
        try """
        version: 1

        ignore:
          commit: false
          patterns:
            - ".env*"
        """.write(
            to: fixtureDirectory.appendingPathComponent(".offsend.yml"),
            atomically: true,
            encoding: .utf8
        )

        let scanner = RepositoryScanner()
        let report = try scanner.scan(directoryURL: fixtureDirectory, toolVersion: "test")
        let object = try JSONSerialization.jsonObject(with: Data(report.json.utf8)) as! [String: Any]
        let presence = object["ignoreFilesPresent"] as! [String: Bool]
        XCTAssertEqual(presence["cursor-ignore"], true)
        XCTAssertEqual(presence["claude-ignore"], true)
        // Context files not materialized by `offsend sync` keep real presence.
        XCTAssertEqual(presence["agents-md"], false)
    }

    func testScanEmptyDirectoryCompletesWithoutExposure() throws {
        let emptyDir = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptyDir) }
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        let scanner = RepositoryScanner()
        let report = try scanner.scan(directoryURL: emptyDir, toolVersion: "test")
        let object = try JSONSerialization.jsonObject(with: Data(report.json.utf8)) as! [String: Any]
        let exposed = object["exposedPatterns"] as? [[String: Any]] ?? []
        XCTAssertTrue(exposed.isEmpty)
        let totals = object["totals"] as? [String: Any]
        XCTAssertEqual(totals?["exposedFiles"] as? Int, 0)
    }

    private func createFixture() throws {
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        try ".env\nSECRET=abc".write(
            to: fixtureDirectory.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        try "# readme".write(
            to: fixtureDirectory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}

final class RepositoryClonerTests: XCTestCase {
    func testCloneFailsWhenGitMissing() async {
        let cloner = RepositoryCloner(
            gitPath: "/nonexistent/git-\(UUID().uuidString)",
            timeout: .seconds(5)
        )
        let destination = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        do {
            try await cloner.clone(
                repositoryURL: URL(string: "https://github.com/org/repo")!,
                into: destination
            )
            XCTFail("Expected git unavailable error")
        } catch let error as RepositoryCloneError {
            if case let .gitUnavailable(path) = error {
                XCTAssertTrue(path.contains("nonexistent/git-"))
            } else {
                XCTFail("Expected gitUnavailable, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRemoveCloneDeletesDirectory() throws {
        let cloner = RepositoryCloner(gitPath: "/usr/bin/git", timeout: .seconds(5))
        let cloneDir = TestSupport.temporaryDirectory()
        try FileManager.default.createDirectory(at: cloneDir, withIntermediateDirectories: true)
        try "content".write(to: cloneDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        cloner.removeClone(at: cloneDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloneDir.path))
    }
}

final class ScanJobRunnerTests: XCTestCase {
    private var workDirectory: URL!
    private var reportDirectory: URL!
    private var htmlTemplates: HTMLTemplateRenderer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workDirectory = TestSupport.temporaryDirectory()
        reportDirectory = TestSupport.temporaryDirectory()
        htmlTemplates = try HTMLTemplateRenderer.load()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDirectory)
        try? FileManager.default.removeItem(at: reportDirectory)
        super.tearDown()
    }

    func testRunMarksJobFailedWhenGitUnavailable() async {
        let jobStore = JobStore(ttl: .seconds(3600))
        let jobID = "job-fail-1"
        _ = await jobStore.create(id: jobID, repoURL: "https://github.com/org/repo")

        let services = ScanServices(
            jobStore: jobStore,
            cloner: RepositoryCloner(
                gitPath: "/nonexistent/git-\(UUID().uuidString)",
                timeout: .seconds(5)
            ),
            scanner: RepositoryScanner(),
            reportStorage: ReportStorageBox(LocalReportStorage(directory: reportDirectory)),
            htmlTemplates: htmlTemplates,
            workDirectory: workDirectory,
            toolVersion: "test",
            logger: Logger(label: "test")
        )

        await ScanJobRunner.run(
            parameters: ScanRepositoryJobParameters(jobID: jobID, repoURL: "https://github.com/org/repo"),
            services: services
        )

        let record = await jobStore.get(jobID)
        XCTAssertEqual(record?.status, .failed)
        XCTAssertNotNil(record?.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDirectory.appendingPathComponent(jobID).path))
    }

    func testRunMarksJobFailedForInvalidRepoURLInParameters() async {
        let jobStore = JobStore(ttl: .seconds(3600))
        let jobID = "job-fail-2"
        _ = await jobStore.create(id: jobID, repoURL: "https://github.com/org/repo")

        let services = ScanServices(
            jobStore: jobStore,
            cloner: RepositoryCloner(gitPath: "/usr/bin/git", timeout: .seconds(5)),
            scanner: RepositoryScanner(),
            reportStorage: ReportStorageBox(LocalReportStorage(directory: reportDirectory)),
            htmlTemplates: htmlTemplates,
            workDirectory: workDirectory,
            toolVersion: "test",
            logger: Logger(label: "test")
        )

        await ScanJobRunner.run(
            parameters: ScanRepositoryJobParameters(jobID: jobID, repoURL: "https://github.com/only-one-segment"),
            services: services
        )

        let record = await jobStore.get(jobID)
        XCTAssertEqual(record?.status, .failed)
        XCTAssertTrue(record?.errorMessage?.contains("repository") == true)
    }

    func testRunMarksRunningBeforeProcessing() async {
        let jobStore = JobStore(ttl: .seconds(3600))
        let jobID = "job-running"
        _ = await jobStore.create(id: jobID, repoURL: "https://github.com/org/repo")

        let services = ScanServices(
            jobStore: jobStore,
            cloner: RepositoryCloner(
                gitPath: "/nonexistent/git-\(UUID().uuidString)",
                timeout: .seconds(5)
            ),
            scanner: RepositoryScanner(),
            reportStorage: ReportStorageBox(LocalReportStorage(directory: reportDirectory)),
            htmlTemplates: htmlTemplates,
            workDirectory: workDirectory,
            toolVersion: "test",
            logger: Logger(label: "test")
        )

        await ScanJobRunner.run(
            parameters: ScanRepositoryJobParameters(jobID: jobID, repoURL: "https://github.com/org/repo"),
            services: services
        )

        let record = await jobStore.get(jobID)
        XCTAssertEqual(record?.status, .failed)
    }
}
