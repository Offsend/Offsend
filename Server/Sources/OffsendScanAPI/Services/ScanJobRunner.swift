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
    var scanTimeout: Duration = .seconds(180)
    var maxRepoSizeBytes: Int64 = 500 * 1024 * 1024
}

enum ScanJobError: Error, Sendable {
    case repositoryTooLarge
    case scanTimedOut
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

            let cloneSize = directorySize(at: cloneDestination)
            guard cloneSize <= services.maxRepoSizeBytes else {
                throw ScanJobError.repositoryTooLarge
            }

            let scanner = services.scanner
            let report = try await withDeadline(services.scanTimeout) {
                scanner.scan(directoryURL: cloneDestination)
            }
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
            await services.jobStore.markFailed(parameters.jobID, message: publicFailureMessage(for: error))
            services.logger.error(
                "Scan failed",
                metadata: ["jobID": .string(parameters.jobID), "error": .string(String(describing: error))]
            )
        }

        services.cloner.removeClone(at: cloneDestination)
    }

    /// User-facing failure text. Raw git stderr can leak server paths and
    /// environment details, so it stays in the logs only.
    private static func publicFailureMessage(for error: Error) -> String {
        switch error {
        case let urlError as RepositoryURLError:
            return urlError.errorDescription ?? "Invalid repository URL."
        case RepositoryCloneError.timedOut:
            return "Repository clone timed out."
        case RepositoryCloneError.failed:
            return "Repository clone failed. Check that the repository exists and is publicly accessible."
        case RepositoryCloneError.gitUnavailable:
            return "The scanner is temporarily unavailable. Try again later."
        case ScanJobError.repositoryTooLarge:
            return "Repository is too large to scan."
        case ScanJobError.scanTimedOut:
            return "Scan timed out."
        default:
            return "Scan failed due to an internal error."
        }
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    /// Runs synchronous scan work off the current task and abandons it when the
    /// deadline passes. The abandoned work finishes in the background and its
    /// result is discarded — the scanner has no cooperative cancellation.
    private static func withDeadline<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () -> T
    ) async throws -> T {
        let work = Task.detached { operation() }
        let result: T? = await withTaskGroup(of: T?.self) { group in
            group.addTask { await work.value }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let result else {
            work.cancel()
            throw ScanJobError.scanTimedOut
        }
        return result
    }
}
