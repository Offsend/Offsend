import Foundation
import HTTPTypes
import Hummingbird

enum PageMetadata {
    static let landingTitle = "See what AI can read while you build | Offsend Check"
    static let landingDescription =
        "Free GitHub repository scan for AI privacy risks. Find exposed secrets, sensitive configs, and missing AI ignore rules — no signup required."

    private static let forwardedProto = HTTPField.Name("X-Forwarded-Proto")!

    static let robotsTXT = """
    User-agent: *
    Allow: /
    Disallow: /r/
    Disallow: /scan/

    """

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
            "ogImageURL": "\(siteURL)/assets/logo.svg",
        ]
    }
}
