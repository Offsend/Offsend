import Foundation
import Hummingbird

enum StaticAssets {
    enum LoadError: Error {
        case missingResources
        case notFound(String)
    }

    private static let allowedExtensions: Set<String> = ["css", "svg", "png", "jpg", "jpeg", "ico", "js"]

    /// Bundled files whose content contributes to ``version`` (cache-bust query).
    private static let versionedFilenames: [String] = [
        "favicon.ico",
        "landing.js",
        "logo.svg",
        "nav.js",
        "og.jpg",
        "polling.js",
        "report.js",
        "site.css",
    ]

    private static let contentTypes: [String: String] = [
        "css": "text/css; charset=utf-8",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "ico": "image/x-icon",
        "js": "text/javascript; charset=utf-8",
    ]

    /// Stable fingerprint of bundled static assets for `?v=` cache busting.
    /// Changes only when asset bytes change — same across machines/restarts.
    static let version: String = {
        guard let baseURL = Bundle.module.resourceURL else { return "0" }
        var hash: UInt64 = 5381
        for name in versionedFilenames {
            guard let fileURL = resolveFileURL(named: name, baseURL: baseURL),
                  let data = try? Data(contentsOf: fileURL)
            else { continue }
            for byte in data {
                hash = ((hash << 5) &+ hash) &+ UInt64(byte)
            }
        }
        return String(hash, radix: 16)
    }()

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

        guard let fileURL = resolveFileURL(named: normalized, baseURL: baseURL) else {
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
                // URLs are versioned via ?v= — safe to cache aggressively.
                .cacheControl: "public, max-age=31536000, immutable",
            ],
            body: .init(byteBuffer: buffer)
        )
    }

    /// Swift `.process("Resources")` flattens Static/ into the bundle root.
    private static func resolveFileURL(named name: String, baseURL: URL) -> URL? {
        let candidates = [
            baseURL.appendingPathComponent(name),
            baseURL.appendingPathComponent("Static").appendingPathComponent(name),
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }
}
