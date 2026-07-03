import HTTPTypes
import Hummingbird

/// Adds standard security headers to every response. Page scripts are served
/// from /assets; Google Analytics and Google Fonts require additional sources.
struct SecurityHeadersMiddleware<Context: RequestContext>: RouterMiddleware {
    private static var contentSecurityPolicy: String {
        [
            "default-src 'self'",
            "script-src 'self' 'unsafe-inline' https://www.googletagmanager.com",
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
            "font-src https://fonts.gstatic.com",
            "img-src 'self' data:",
            "connect-src 'self' https://www.google-analytics.com https://analytics.google.com https://*.google-analytics.com",
            "object-src 'none'",
            "frame-ancestors 'none'",
            "base-uri 'self'",
            "form-action 'self'",
        ].joined(separator: "; ")
    }

    private static var headers: [(HTTPField.Name, String)] {
        [
            (HTTPField.Name("Content-Security-Policy")!, contentSecurityPolicy),
            (HTTPField.Name("X-Content-Type-Options")!, "nosniff"),
            (HTTPField.Name("X-Frame-Options")!, "DENY"),
            (HTTPField.Name("Referrer-Policy")!, "strict-origin-when-cross-origin"),
        ]
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        var response = try await next(request, context)
        for (name, value) in Self.headers {
            response.headers[name] = value
        }
        return response
    }
}
