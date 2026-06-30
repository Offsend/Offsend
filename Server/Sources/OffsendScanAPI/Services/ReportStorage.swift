import Foundation
import Logging
import NIOCore
import SotoCore
import SotoS3

protocol ReportStorage: Sendable {
    func storeHTML(jobID: String, html: String) async throws -> String
    func loadHTML(jobID: String) async throws -> String?
}

struct LocalReportStorage: ReportStorage, @unchecked Sendable {
    let directory: URL
    let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func storeHTML(jobID: String, html: String) async throws -> String {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(jobID).html")
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }

    func loadHTML(jobID: String) async throws -> String? {
        let fileURL = directory.appendingPathComponent("\(jobID).html")
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}

struct R2ReportStorage: ReportStorage, @unchecked Sendable {
    let bucket: String
    let keyPrefix: String
    let publicBaseURL: URL?
    let s3: S3
    let localFallback: LocalReportStorage
    let logger: Logger

    func storeHTML(jobID: String, html: String) async throws -> String {
        let key = "\(keyPrefix)/\(jobID).html"
        let body = AWSHTTPBody(string: html)
        _ = try await s3.putObject(
            S3.PutObjectRequest(
                body: body,
                bucket: bucket,
                cacheControl: "public, max-age=3600",
                contentType: "text/html; charset=utf-8",
                key: key
            )
        )
        logger.info("Stored report HTML in R2", metadata: ["key": .string(key)])
        _ = try? await localFallback.storeHTML(jobID: jobID, html: html)
        return key
    }

    func loadHTML(jobID: String) async throws -> String? {
        if let local = try await localFallback.loadHTML(jobID: jobID) {
            return local
        }
        let key = "\(keyPrefix)/\(jobID).html"
        do {
            let response = try await s3.getObject(S3.GetObjectRequest(bucket: bucket, key: key))
            let data = try await response.body.collect(upTo: 10 * 1024 * 1024)
            return String(data: Data(buffer: data), encoding: .utf8)
        } catch {
            logger.debug("R2 report not found", metadata: ["key": .string(key)])
            return nil
        }
    }
}

enum ReportStorageFactory {
    static func make(config: AppConfiguration, logger: Logger) async throws -> any ReportStorage {
        try FileManager.default.createDirectory(at: config.reportStorageDirectory, withIntermediateDirectories: true)
        let local = LocalReportStorage(directory: config.reportStorageDirectory)

        guard let r2 = config.r2 else {
            logger.info("Report storage: local filesystem")
            return local
        }

        let client = AWSClient(
            credentialProvider: .static(
                accessKeyId: r2.accessKeyID,
                secretAccessKey: r2.secretAccessKey
            )
        )
        let endpoint = "https://\(r2.accountID).r2.cloudflarestorage.com"
        let s3 = S3(client: client, region: .euwest1, endpoint: endpoint)
        logger.info("Report storage: Cloudflare R2", metadata: ["bucket": .string(r2.bucket)])
        return R2ReportStorage(
            bucket: r2.bucket,
            keyPrefix: "reports",
            publicBaseURL: r2.publicBaseURL,
            s3: s3,
            localFallback: local,
            logger: logger
        )
    }
}
