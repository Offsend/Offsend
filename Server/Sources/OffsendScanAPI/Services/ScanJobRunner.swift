import Foundation
import Jobs
import Logging

struct ScanRepositoryJobParameters: JobParameters {
    static let jobName = "ScanRepository"
    let jobID: String
    let repoURL: String
}

struct ScanServices: @unchecked Sendable {
    let jobStore: JobStore
    let cloner: RepositoryCloner
    let scanner: RepositoryScanner
    let reportStorage: ReportStorageBox
    let htmlTemplates: HTMLTemplateRenderer
    let workDirectory: URL
    let toolVersion: String
    let logger: Logger
    var reportTTL: Duration = .seconds(172_800)
}

/// Type-erased report storage so job handlers stay Sendable.
struct ReportStorageBox: Sendable {
    private let _store: @Sendable (String, String) async throws -> String
    private let _load: @Sendable (String) async throws -> String?

    init(_ storage: any ReportStorage) {
        _store = { jobID, html in try await storage.storeHTML(jobID: jobID, html: html) }
        _load = { jobID in try await storage.loadHTML(jobID: jobID) }
    }

    func storeHTML(jobID: String, html: String) async throws -> String {
        try await _store(jobID, html)
    }

    func loadHTML(jobID: String) async throws -> String? {
        try await _load(jobID)
    }
}

enum ScanJobRunner {
    static func run(parameters: ScanRepositoryJobParameters, services: ScanServices) async {
        await services.jobStore.markRunning(parameters.jobID)
        let cloneDestination = services.workDirectory.appendingPathComponent(parameters.jobID, isDirectory: true)

        do {
            let normalized = try RepositoryURLValidator.normalize(parameters.repoURL)
            try await services.cloner.clone(repositoryURL: normalized, into: cloneDestination)

            let report = services.scanner.scan(directoryURL: cloneDestination)
            let reportJSON = services.scanner.renderJSON(report, toolVersion: services.toolVersion)
            let html = try ReportHTMLRenderer.render(
                templates: services.htmlTemplates,
                jobID: parameters.jobID,
                repoURL: normalized.absoluteString,
                reportJSON: reportJSON,
                generatedAt: Date(),
                reportTTL: services.reportTTL
            )
            let storageKey = try await services.reportStorage.storeHTML(jobID: parameters.jobID, html: html)
            await services.jobStore.markCompleted(parameters.jobID, reportJSON: reportJSON, reportHTMLKey: storageKey)

            if report.hasErrors {
                services.logger.warning(
                    "Scan completed with report errors",
                    metadata: ["jobID": .string(parameters.jobID), "errors": .string(report.errorIDs.joined(separator: ","))]
                )
            } else {
                services.logger.info("Scan completed", metadata: ["jobID": .string(parameters.jobID)])
            }
        } catch {
            await services.jobStore.markFailed(parameters.jobID, message: error.localizedDescription)
            services.logger.error("Scan failed", metadata: ["jobID": .string(parameters.jobID), "error": .string(error.localizedDescription)])
        }

        services.cloner.removeClone(at: cloneDestination)
    }
}
