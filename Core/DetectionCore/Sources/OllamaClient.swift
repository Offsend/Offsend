import Foundation

public struct OllamaModelSummary: Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public enum OllamaClientError: Error, Equatable, Sendable {
    case invalidEndpoint
    case modelNotFound(String)
    case requestFailed(String)
    case invalidResponse
}

extension OllamaClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Ollama endpoint must use http://127.0.0.1 or http://localhost."
        case .modelNotFound(let name):
            return "Ollama model not found: \(name). Pull it with `ollama pull` first."
        case .requestFailed(let message):
            return message
        case .invalidResponse:
            return "Ollama returned an unexpected response."
        }
    }
}

public final class OllamaClient: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    /// Bounds short control calls (list/exists/create/delete) so a hung daemon can't pin the caller's thread.
    private let requestTimeout: TimeInterval
    /// Generation can be slow on large local models, so it gets a longer ceiling than control calls.
    private let generateTimeout: TimeInterval

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 30,
        generateTimeout: TimeInterval = 120
    ) {
        self.baseURL = baseURL
        self.session = session
        self.requestTimeout = requestTimeout
        self.generateTimeout = generateTimeout
    }

    public static func normalizedLocalEndpoint(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "http://\(trimmed)"
        }
        guard let url = URL(string: withScheme) else {
            throw OllamaClientError.invalidEndpoint
        }
        try validateLocalEndpoint(url)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        guard let normalized = components?.url else {
            throw OllamaClientError.invalidEndpoint
        }
        return normalized
    }

    public static func validateLocalEndpoint(_ url: URL) throws {
        guard url.scheme?.lowercased() == "http" else {
            throw OllamaClientError.invalidEndpoint
        }
        guard let host = url.host?.lowercased() else {
            throw OllamaClientError.invalidEndpoint
        }
        let allowed = Set(["127.0.0.1", "localhost", "::1", "0.0.0.0"])
        guard allowed.contains(host) else {
            throw OllamaClientError.invalidEndpoint
        }
    }

    public func listModels() async throws -> [OllamaModelSummary] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)
        struct TagsResponse: Decodable {
            struct Model: Decodable {
                let name: String
            }
            let models: [Model]
        }
        guard let decoded = try? decoder.decode(TagsResponse.self, from: data) else {
            throw OllamaClientError.invalidResponse
        }
        return decoded.models.map { OllamaModelSummary(name: $0.name) }
    }

    public func modelExists(_ modelName: String) async throws -> Bool {
        let models = try await listModels()
        let normalized = modelName.lowercased()
        return models.contains { $0.name.lowercased() == normalized || $0.name.lowercased().hasPrefix("\(normalized):") }
    }

    public func deleteModel(name: String) async throws {
        let url = baseURL.appendingPathComponent("api/delete")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeleteRequest(name: name))

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)
    }

    /// Registers a local GGUF file as an Ollama model via the modern `/api/blobs` + `/api/create`
    /// flow (Ollama >= 0.5.5). The legacy `modelfile` field was removed from the create API.
    public func createModel(name: String, ggufFileURL: URL) async throws {
        let digest = try AIModelChecksumValidator.sha256(of: ggufFileURL)
        try await uploadBlobIfMissing(digest: digest, fileURL: ggufFileURL)

        let url = baseURL.appendingPathComponent("api/create")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = generateTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            CreateRequest(
                model: name,
                files: [ggufFileURL.lastPathComponent: "sha256:\(digest)"],
                stream: false
            )
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)
    }

    private func uploadBlobIfMissing(digest: String, fileURL: URL) async throws {
        guard let blobURL = URL(string: "api/blobs/sha256:\(digest)", relativeTo: baseURL) else {
            throw OllamaClientError.invalidEndpoint
        }

        var headRequest = URLRequest(url: blobURL)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = requestTimeout
        let (_, headResponse) = try await session.data(for: headRequest)
        if let http = headResponse as? HTTPURLResponse, http.statusCode == 200 {
            return
        }

        var uploadRequest = URLRequest(url: blobURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.timeoutInterval = generateTimeout
        let (data, response) = try await session.upload(for: uploadRequest, fromFile: fileURL)
        try validateHTTP(response, data: data)
    }

    public func generateJSON(model: String, prompt: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = generateTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateRequest(
                model: model,
                prompt: prompt,
                stream: false,
                format: "json",
                options: GenerateRequest.Options(temperature: 0)
            )
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)
        struct GenerateResponse: Decodable {
            let response: String?
            let error: String?
        }
        guard let decoded = try? decoder.decode(GenerateResponse.self, from: data) else {
            throw OllamaClientError.invalidResponse
        }
        if let error = decoded.error, !error.isEmpty {
            throw OllamaClientError.requestFailed(error)
        }
        guard let text = decoded.response, !text.isEmpty else {
            throw OllamaClientError.invalidResponse
        }
        return text
    }

    private func validateHTTP(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ... 299).contains(http.statusCode) else {
            // Ollama returns errors as `{"error": "..."}`; surface that message when present.
            struct ErrorResponse: Decodable {
                let error: String?
            }
            if let data,
               let decoded = try? decoder.decode(ErrorResponse.self, from: data),
               let message = decoded.error, !message.isEmpty {
                throw OllamaClientError.requestFailed(message)
            }
            throw OllamaClientError.requestFailed("Ollama HTTP \(http.statusCode).")
        }
    }

    private struct DeleteRequest: Encodable {
        let name: String
    }

    private struct CreateRequest: Encodable {
        let model: String
        let files: [String: String]
        let stream: Bool
    }

    private struct GenerateRequest: Encodable {
        struct Options: Encodable {
            let temperature: Double
        }

        let model: String
        let prompt: String
        let stream: Bool
        let format: String
        let options: Options
    }
}
