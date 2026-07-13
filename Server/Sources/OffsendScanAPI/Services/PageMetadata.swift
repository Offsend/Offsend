import Foundation
import HTTPTypes
import Hummingbird

enum PageMetadata {
    static let landingTitle = "See what AI can read while you build | Offsend Check"
    static let landingDescription =
        "Free GitHub repository scan for AI privacy risks. Find exposed secrets, sensitive configs, and missing AI ignore rules — no signup required."

    private static let forwardedProto = HTTPField.Name("X-Forwarded-Proto")!

    static let defaultPublicBaseURL = "https://check.offsend.io"

    static let robotsTXT = """
    User-agent: *
    Allow: /
    Disallow: /r/
    Disallow: /scan/

    Sitemap: \(defaultPublicBaseURL)/sitemap.xml
    """

    /// Indexable public pages only — scan jobs and reports stay out of the sitemap.
    static func sitemapXML(baseURL: String = defaultPublicBaseURL) -> String {
        let origin = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url>
            <loc>\(origin)/</loc>
            <changefreq>weekly</changefreq>
            <priority>1.0</priority>
          </url>
        </urlset>
        """
    }

    static func siteURL(from request: Request) -> String {
        let host = request.head.authority ?? "localhost"
        let scheme = request.headers[forwardedProto]
            ?? request.head.scheme
            ?? ((host.hasPrefix("localhost") || host.hasPrefix("127.0.0.1")) ? "http" : "https")
        return "\(scheme)://\(host)"
    }

    static func canonicalURL(from request: Request, path: String = "/") -> String {
        let base = siteURL(from: request)
        guard path != "/" else { return "\(base)/" }
        return "\(base)\(path.hasPrefix("/") ? path : "/\(path)")"
    }

    static func landingContext(siteURL: String) -> [String: Any] {
        let canonical = siteURL.hasSuffix("/") ? siteURL : "\(siteURL)/"
        return [
            "indexPage": true,
            "metaDescription": landingDescription,
            "canonicalURL": canonical,
            "ogTitle": landingTitle,
            "ogDescription": landingDescription,
            "ogImageURL": "\(siteURL)/assets/og.jpg",
        ]
    }
}
