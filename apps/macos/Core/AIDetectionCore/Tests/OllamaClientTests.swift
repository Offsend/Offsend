import XCTest
import DetectionCore
@testable import AIDetectionCore

final class OllamaClientTests: XCTestCase {
    func testNormalizesLocalhostEndpoint() throws {
        let url = try OllamaClient.normalizedLocalEndpoint("127.0.0.1:11434")
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, 11_434)
    }

    func testRejectsRemoteEndpoint() {
        XCTAssertThrowsError(try OllamaClient.normalizedLocalEndpoint("http://example.com:11434")) { error in
            XCTAssertEqual(error as? OllamaClientError, .invalidEndpoint)
        }
    }

    func testGGUFOllamaModelNameSanitizesID() {
        XCTAssertEqual(
            GGUFModelRunner.ollamaModelName(for: "exdsgift/NerGuard"),
            "offsend-gguf-exdsgift-nerguard"
        )
    }

    func testOllamaModelIDAcceptsCommonNames() throws {
        let endpoint = try OllamaClient.normalizedLocalEndpoint("127.0.0.1:11434")
        XCTAssertEqual(
            try OllamaModelImporter.modelID(endpoint: endpoint, modelName: "llama3.2:latest"),
            "ollama-127.0.0.1-11434-llama3.2-latest"
        )
        XCTAssertEqual(
            try OllamaModelImporter.modelID(endpoint: endpoint, modelName: "library/phi3:mini"),
            "ollama-127.0.0.1-11434-library-phi3-mini"
        )
    }

    func testOllamaModelIDRejectsUnsafeNames() throws {
        let endpoint = try OllamaClient.normalizedLocalEndpoint("127.0.0.1:11434")
        XCTAssertThrowsError(try OllamaModelImporter.modelID(endpoint: endpoint, modelName: "../evil"))
        XCTAssertThrowsError(try OllamaModelImporter.modelID(endpoint: endpoint, modelName: "name;rm"))
        XCTAssertFalse(OllamaModelImporter.isSafeModelName("a b"))
    }

    func testCreateModelUploadsBlobThenCreatesWithFilesMapping() async throws {
        let ggufURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gguf")
        try Data("fake gguf weights".utf8).write(to: ggufURL)
        defer { try? FileManager.default.removeItem(at: ggufURL) }
        let digest = try AIModelChecksumValidator.sha256(of: ggufURL)

        let recorder = RequestRecorder()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaMockURLProtocol.self]
        OllamaMockURLProtocol.requestHandler = { request in
            let record = RequestRecord(
                method: request.httpMethod ?? "",
                path: request.url?.path ?? "",
                body: request.httpMethod == "POST" && request.url?.path.hasSuffix("/api/create") == true
                    ? OllamaMockURLProtocol.bodyData(from: request)
                    : Data()
            )
            recorder.append(record)
            // The blob does not exist yet, so HEAD must answer 404 and force the upload.
            let status = request.httpMethod == "HEAD" ? 404 : 200
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = OllamaClient(
            baseURL: URL(string: "http://127.0.0.1:11434")!,
            session: URLSession(configuration: config)
        )
        try await client.createModel(name: "offsend-gguf-demo", ggufFileURL: ggufURL)

        let records = recorder.snapshot()
        XCTAssertEqual(records.map(\.method), ["HEAD", "POST", "POST"])
        XCTAssertEqual(records[0].path, "/api/blobs/sha256:\(digest)")
        XCTAssertEqual(records[1].path, "/api/blobs/sha256:\(digest)")
        XCTAssertEqual(records[2].path, "/api/create")

        struct CreatePayload: Decodable {
            let model: String
            let files: [String: String]
            let stream: Bool
        }
        let payload = try JSONDecoder().decode(CreatePayload.self, from: records[2].body)
        XCTAssertEqual(payload.model, "offsend-gguf-demo")
        XCTAssertEqual(payload.files, [ggufURL.lastPathComponent: "sha256:\(digest)"])
        XCTAssertFalse(payload.stream)
    }

    func testCreateModelSkipsBlobUploadWhenBlobExists() async throws {
        let ggufURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gguf")
        try Data("fake gguf weights".utf8).write(to: ggufURL)
        defer { try? FileManager.default.removeItem(at: ggufURL) }

        let recorder = RequestRecorder()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaMockURLProtocol.self]
        OllamaMockURLProtocol.requestHandler = { request in
            recorder.append(
                RequestRecord(method: request.httpMethod ?? "", path: request.url?.path ?? "", body: Data())
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = OllamaClient(
            baseURL: URL(string: "http://127.0.0.1:11434")!,
            session: URLSession(configuration: config)
        )
        try await client.createModel(name: "offsend-gguf-demo", ggufFileURL: ggufURL)

        let records = recorder.snapshot()
        XCTAssertEqual(records.map(\.method), ["HEAD", "POST"], "Existing blob must not be re-uploaded")
        XCTAssertEqual(records.last?.path, "/api/create")
    }

    func testDeleteModelSendsDeleteRequest() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaMockURLProtocol.self]
        OllamaMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/delete") == true)
            let bodyData = OllamaMockURLProtocol.bodyData(from: request)
            struct DeletePayload: Decodable {
                let name: String
            }
            let payload = try JSONDecoder().decode(DeletePayload.self, from: bodyData)
            XCTAssertEqual(payload.name, "offsend-gguf-demo")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = OllamaClient(
            baseURL: URL(string: "http://127.0.0.1:11434")!,
            session: URLSession(configuration: config)
        )
        try await client.deleteModel(name: "offsend-gguf-demo")
    }
}

private struct RequestRecord {
    let method: String
    let path: String
    let body: Data
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [RequestRecord] = []

    func append(_ record: RequestRecord) {
        lock.withLock { records.append(record) }
    }

    func snapshot() -> [RequestRecord] {
        lock.withLock { records }
    }
}

private final class OllamaMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            XCTFail("Missing HTTP body")
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
