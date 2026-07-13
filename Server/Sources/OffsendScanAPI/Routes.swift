import Foundation
import HTTPTypes
import Hummingbird

enum Routes {
    private static let flyClientIP = HTTPField.Name("Fly-Client-IP")!
    private static let xForwardedFor = HTTPField.Name("X-Forwarded-For")!

    static func buildRouter(dependencies: AppDependencies) -> Router<AppRequestContext> {
        let router = Router(context: AppRequestContext.self)
        router.add(middleware: SecurityHeadersMiddleware())
        let templates = dependencies.htmlTemplates

        router.get("/health") { _, _ in
            "ok"
        }

        router.get("/robots.txt") { _, _ in
            Response(
                status: .ok,
                headers: [.contentType: "text/plain; charset=utf-8"],
                body: .init(byteBuffer: .init(string: PageMetadata.robotsTXT))
            )
        }

        router.get("/sitemap.xml") { _, _ in
            let baseURL = dependencies.config.publicBaseURL ?? PageMetadata.defaultPublicBaseURL
            return Response(
                status: .ok,
                headers: [.contentType: "application/xml; charset=utf-8"],
                body: .init(byteBuffer: .init(string: PageMetadata.sitemapXML(baseURL: baseURL)))
            )
        }

        router.get("/favicon.ico") { _, _ in
            do {
                return try StaticAssets.response(for: "favicon.ico")
            } catch StaticAssets.LoadError.notFound {
                throw HTTPError(.notFound)
            }
        }

        router.get("/assets/:filename") { _, context in
            guard let filename = context.parameters.get("filename") else {
                throw HTTPError(.badRequest)
            }
            do {
                return try StaticAssets.response(for: filename)
            } catch StaticAssets.LoadError.notFound {
                throw HTTPError(.notFound)
            }
        }

        router.get("/") { request, _ in
            let siteURL = dependencies.config.publicBaseURL ?? PageMetadata.siteURL(from: request)
            let html = try templates.landingPage(siteURL: siteURL)
            return Response(
                status: .ok,
                headers: [.contentType: "text/html; charset=utf-8"],
                body: .init(byteBuffer: .init(string: html))
            )
        }

        router.post("/scan") { request, context in
            guard await dependencies.rateLimiter.allow(clientKey(for: request)) else {
                throw HTTPError(.tooManyRequests, message: "Too many scan requests. Try again in a minute.")
            }

            let payload = try await request.decode(as: CreateScanRequest.self, context: context)
            let normalized = try RepositoryURLValidator.normalize(payload.url)

            // Reuse an in-flight or recently completed scan of the same repo
            // instead of queueing duplicate work.
            if let existing = await dependencies.jobStore.reusableJob(
                repoURL: normalized.absoluteString,
                completedWithin: dependencies.config.scanReuseWindow
            ) {
                return try jsonResponse(
                    scanCreatedResponse(jobID: existing.id),
                    status: .accepted,
                    location: "/scan/\(existing.id)"
                )
            }

            guard await dependencies.jobStore.pendingCount() < dependencies.config.maxPendingScans else {
                throw HTTPError(.serviceUnavailable, message: "Scanner is at capacity. Try again shortly.")
            }

            let jobID = UUID().uuidString.lowercased()
            _ = await dependencies.jobStore.create(id: jobID, repoURL: normalized.absoluteString)
            try await dependencies.pushScanJob(
                ScanRepositoryJobParameters(jobID: jobID, repoURL: normalized.absoluteString)
            )

            return try jsonResponse(
                scanCreatedResponse(jobID: jobID),
                status: .accepted,
                location: "/scan/\(jobID)"
            )
        }

        router.get("/scan/:id") { _, context in
            let id = try jobID(from: context)
            guard let record = await dependencies.jobStore.get(id) else {
                throw HTTPError(.notFound)
            }

            let reportPayload = record.reportJSON.flatMap { ScanStatusResponse.ReportPayload.decode(from: $0) }
            let response = ScanStatusResponse(
                jobID: record.id,
                repoURL: record.repoURL,
                status: record.status,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                reportURL: record.reportURL,
                errorMessage: record.errorMessage,
                report: reportPayload
            )
            return try jsonResponse(response)
        }

        #if DEBUG
        router.get("/scan/page") { _, _ in
            let html = try templates.pollingPreviewPage()
            return Response(
                status: .ok,
                headers: [.contentType: "text/html; charset=utf-8"],
                body: .init(byteBuffer: .init(string: html))
            )
        }
        #endif

        router.get("/scan/:id/page") { _, context in
            let id = try jobID(from: context)
            let html = try templates.pollingPage(jobID: id)
            return Response(
                status: .ok,
                headers: [.contentType: "text/html; charset=utf-8"],
                body: .init(byteBuffer: .init(string: html))
            )
        }

        router.get("/r/:id") { _, context in
            let id = try jobID(from: context)
            // A record in a non-completed state means the scan is still in flight.
            // A missing record can also mean the server restarted after the scan
            // finished, so fall through to storage, which is the source of truth.
            if let record = await dependencies.jobStore.get(id), record.status != .completed {
                throw HTTPError(.conflict)
            }

            if let html = try await dependencies.reportStorage.loadHTML(jobID: id) {
                return Response(
                    status: .ok,
                    headers: [.contentType: "text/html; charset=utf-8"],
                    body: .init(byteBuffer: .init(string: html))
                )
            }
            throw HTTPError(.notFound)
        }

        return router
    }

    /// Job IDs are server-generated UUIDs; restricting the charset keeps raw path
    /// input away from filesystem paths and storage keys.
    private static func jobID(from context: AppRequestContext) throws -> String {
        guard let id = context.parameters.get("id"),
              !id.isEmpty,
              id.count <= 64,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw HTTPError(.notFound)
        }
        return id
    }

    private static func scanCreatedResponse(jobID: String) -> CreateScanResponse {
        CreateScanResponse(
            jobID: jobID,
            statusURL: "/scan/\(jobID)",
            reportURL: "/r/\(jobID)",
            pollIntervalMs: 2000
        )
    }

    private static func jsonResponse(
        _ value: some Encodable,
        status: HTTPResponse.Status = .ok,
        location: String? = nil
    ) throws -> Response {
        let data = try JSONEncoder().encode(value)
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        var headers: HTTPFields = [.contentType: "application/json"]
        if let location {
            headers[.location] = location
        }
        return Response(status: status, headers: headers, body: .init(byteBuffer: buffer))
    }

    private static func clientKey(for request: Request) -> String {
        if let ip = request.headers[flyClientIP] {
            return ip
        }
        if let forwarded = request.headers[xForwardedFor],
           let first = forwarded.split(separator: ",").first {
            return first.trimmingCharacters(in: .whitespaces)
        }
        return "unknown"
    }
}
