import Foundation

/// Parsed custom URL (`offsend://…`) for in-app routing.
enum OffsendDeepLink: Equatable, Sendable {
    /// Return from web checkout; optional `email` query pre-fills activation.
    case checkoutSuccess(prefillEmail: String?)
}

/// Extensible registry: append new parsers for additional paths.
enum OffsendDeepLinkParser {
    typealias Parser = (URL) -> OffsendDeepLink?

    /// Ordered list; first non-nil match wins.
    static let parsers: [Parser] = [
        parseCheckoutSuccess
    ]

    static func parse(_ url: URL) -> OffsendDeepLink? {
        for parser in parsers {
            if let link = parser(url) {
                return link
            }
        }
        return nil
    }

    /// `offsend://checkout/success` or `offsend://checkout/success?email=…`
    private static func parseCheckoutSuccess(_ url: URL) -> OffsendDeepLink? {
        guard url.scheme?.lowercased() == "offsend" else { return nil }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let isCheckoutSuccess =
            (host == "checkout" && (path == "/success" || path == "success"))
            || path == "/checkout/success"
            || path == "/checkout/success/"
        guard isCheckoutSuccess else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let trimmed = items.first(where: { $0.name.lowercased() == "email" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        return .checkoutSuccess(prefillEmail: email)
    }
}
