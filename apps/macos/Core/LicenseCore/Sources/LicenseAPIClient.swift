import Foundation

public protocol LicenseAPIClienting: Sendable {
    func postJSON<B: Encodable>(path: String, body: B, bearerToken: String?) async throws -> Data
    func getJSON(path: String, queryItems: [URLQueryItem]) async throws -> Data
}

public final class LicenseAPIClient: LicenseAPIClienting, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder

    public init(configuration: LicenseConfiguration, session: URLSession = .shared) {
        self.baseURL = configuration.apiBaseURL
        self.session = session
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        self.encoder = encoder
    }

    public func postJSON<B: Encodable>(path: String, body: B, bearerToken: String?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw LicenseServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LicenseServiceError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LicenseServiceError.unexpectedResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw LicenseServiceError.transport("HTTP \(http.statusCode): \(snippet.prefix(200))")
        }
        return data
    }

    public func getJSON(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw LicenseServiceError.invalidURL
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let combinedPath = ([basePath, trimmed].filter { !$0.isEmpty }).joined(separator: "/")
        components.path = "/" + combinedPath
        components.queryItems = queryItems
        guard let url = components.url else {
            throw LicenseServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LicenseServiceError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LicenseServiceError.unexpectedResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw LicenseServiceError.transport("HTTP \(http.statusCode): \(snippet.prefix(200))")
        }
        return data
    }
}
