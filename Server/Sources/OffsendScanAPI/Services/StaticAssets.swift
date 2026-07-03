import Foundation
import Hummingbird

enum StaticAssets {
    enum LoadError: Error {
        case missingResources
        case notFound(String)
    }

    private static let allowedExtensions: Set<String> = ["css", "svg", "png", "ico", "js"]

    private static let contentTypes: [String: String] = [
        "css": "text/css; charset=utf-8",
        "svg": "image/svg+xml",
        "png": "image/png",
        "ico": "image/x-icon",
        "js": "text/javascript; charset=utf-8",
    ]

    static func response(for path: String) throws -> Response {
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty, !normalized.contains(".."), !normalized.contains("/") else {
            throw LoadError.notFound(path)
        }

        let ext = (normalized as NSString).pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw LoadError.notFound(path)
        }

        guard let baseURL = Bundle.module.resourceURL else {
            throw LoadError.missingResources
        }

        // Swift `.process("Resources")` flattens Static/ into the bundle root.
        let candidates = [
            baseURL.appendingPathComponent(normalized),
            baseURL.appendingPathComponent("Static").appendingPathComponent(normalized),
        ]

        guard let fileURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw LoadError.notFound(path)
        }

        let data = try Data(contentsOf: fileURL)
        let contentType = contentTypes[ext] ?? "application/octet-stream"

        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        return Response(
            status: .ok,
            headers: [
                .contentType: contentType,
                .cacheControl: "public, max-age=86400",
            ],
            body: .init(byteBuffer: buffer)
        )
    }
}
