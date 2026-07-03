import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
@testable import OffsendScanAPI

actor JobPushTracker {
    private(set) var jobs: [ScanRepositoryJobParameters] = []

    func track(_ job: ScanRepositoryJobParameters) {
        jobs.append(job)
    }
}

enum TestSupport {
    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-scan-tests-\(UUID().uuidString)", isDirectory: true)
    }

    static func makeConfiguration(
        reportDirectory: URL,
        scanReuseWindow: Duration = .seconds(0)
    ) -> AppConfiguration {
        AppConfiguration(
            host: "127.0.0.1",
            port: 8080,
            gitPath: "/usr/bin/git",
            cloneTimeout: .seconds(120),
            scanTimeout: .seconds(180),
            maxRepoSizeMB: 500,
            scanWorkDirectory: reportDirectory.deletingLastPathComponent().appendingPathComponent("work", isDirectory: true),
            reportStorageDirectory: reportDirectory,
            jobStoreDirectory: reportDirectory.appendingPathComponent("jobs", isDirectory: true),
            reportTTL: .seconds(3600),
            scanReuseWindow: scanReuseWindow,
            jobWorkers: 1,
            valkeyHost: nil,
            valkeyPort: 6379,
            valkeyQueueName: "test",
            r2: nil,
            toolVersion: "test-1.0.0",
            publicBaseURL: nil,
            scanRateLimitPerMinute: 1000,
            maxPendingScans: 32
        )
    }

    static func makeDependencies(
        jobStore: JobStore = JobStore(ttl: .seconds(3600)),
        reportDirectory: URL,
        pushTracker: JobPushTracker? = nil
    ) throws -> AppDependencies {
        let storage = LocalReportStorage(directory: reportDirectory)
        let config = makeConfiguration(reportDirectory: reportDirectory)
        let pushScanJob: @Sendable (ScanRepositoryJobParameters) async throws -> Void = { parameters in
            if let pushTracker {
                await pushTracker.track(parameters)
            }
        }
        let htmlTemplates = try HTMLTemplateRenderer.load()
        return AppDependencies(
            config: config,
            jobStore: jobStore,
            reportStorage: ReportStorageBox(storage),
            htmlTemplates: htmlTemplates,
            rateLimiter: ScanRateLimiter(maxRequestsPerWindow: 1000),
            pushScanJob: pushScanJob
        )
    }

    static func makeTestApplication(dependencies: AppDependencies) -> Application<Router<AppRequestContext>.Responder> {
        let router = Routes.buildRouter(dependencies: dependencies)
        return Application(responder: router.buildResponder())
    }

    static func sampleReportJSON(
        scanComplete: Bool = true,
        ignoreFiles: [String: Bool] = ["cursor-ignore": true, "claude-ignore": false],
        exposedPatterns: [[String: Any]] = [
            ["id": "env-files", "severity": "required", "category": "secret", "count": 2],
        ],
        exposedFiles: Int = 2,
        errors: [String] = []
    ) -> String {
        let patternsJSON = exposedPatterns.map { pattern -> String in
            let id = pattern["id"] as! String
            let severity = pattern["severity"] as! String
            let category = pattern["category"] as! String
            let count = pattern["count"] as! Int
            return """
            { "id": "\(id)", "severity": "\(severity)", "category": "\(category)", "count": \(count) }
            """
        }.joined(separator: ",\n          ")

        let ignoreJSON = ignoreFiles
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\": \($0.value)" }
            .joined(separator: ", ")

        let errorsJSON = errors.map { "\"\($0)\"" }.joined(separator: ", ")

        return """
        {
          "schemaVersion": 1,
          "rulesetVersion": "abc",
          "toolVersion": "1.0.0",
          "generatedAt": "2025-01-01T00:00:00Z",
          "scanComplete": \(scanComplete),
          "ignoreFilesPresent": { \(ignoreJSON) },
          "exposedPatterns": [
            \(patternsJSON)
          ],
          "totals": { "exposedFiles": \(exposedFiles), "exposedPatternTypes": \(exposedPatterns.count) },
          "errors": [\(errorsJSON)]
        }
        """
    }
}
