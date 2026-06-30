import Foundation
import Hummingbird

enum Routes {
    static func buildRouter(dependencies: AppDependencies) -> Router<AppRequestContext> {
        let router = Router(context: AppRequestContext.self)
        let templates = dependencies.htmlTemplates

        router.get("/health") { _, _ in
            "ok"
        }

        router.get("/") { _, _ in
            let html = try templates.landingPage()
            return Response(
                status: .ok,
                headers: [.contentType: "text/html; charset=utf-8"],
                body: .init(byteBuffer: .init(string: html))
            )
        }

        router.post("/scan") { request, context in
            let payload = try await request.decode(as: CreateScanRequest.self, context: context)
            let normalized = try RepositoryURLValidator.normalize(payload.url)
            let jobID = UUID().uuidString.lowercased()

            _ = await dependencies.jobStore.create(id: jobID, repoURL: normalized.absoluteString)
            try await dependencies.pushScanJob(
                ScanRepositoryJobParameters(jobID: jobID, repoURL: normalized.absoluteString)
            )

            let response = CreateScanResponse(
                jobID: jobID,
                statusURL: "/scan/\(jobID)",
                reportURL: "/r/\(jobID)",
                pollIntervalMs: 2000
            )
            let data = try JSONEncoder().encode(response)
            var buffer = ByteBuffer()
            buffer.writeBytes(data)
            return Response(
                status: .accepted,
                headers: [.contentType: "application/json", .location: "/scan/\(jobID)"],
                body: .init(byteBuffer: buffer)
            )
        }

        router.get("/scan/:id") { _, context in
            guard let id = context.parameters.get("id") else {
                throw HTTPError(.badRequest)
            }
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
            let data = try JSONEncoder().encode(response)
            var buffer = ByteBuffer()
            buffer.writeBytes(data)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: buffer)
            )
        }

        router.get("/scan/:id/page") { _, context in
            guard let id = context.parameters.get("id") else {
                throw HTTPError(.badRequest)
            }
            let html = try templates.pollingPage(jobID: id)
            return Response(
                status: .ok,
                headers: [.contentType: "text/html; charset=utf-8"],
                body: .init(byteBuffer: .init(string: html))
            )
        }

        router.get("/r/:id") { _, context in
            guard let id = context.parameters.get("id") else {
                throw HTTPError(.badRequest)
            }
            guard let record = await dependencies.jobStore.get(id) else {
                throw HTTPError(.notFound)
            }
            guard record.status == .completed else {
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
}
