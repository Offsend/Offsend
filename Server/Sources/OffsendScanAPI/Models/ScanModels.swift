import Foundation

enum ScanJobStatus: String, Codable, Sendable {
    case queued
    case running
    case completed
    case failed
}

struct ScanJobRecord: Codable, Sendable, Equatable {
    let id: String
    let repoURL: String
    var status: ScanJobStatus
    let createdAt: Date
    var updatedAt: Date
    var reportJSON: String?
    var reportHTMLKey: String?
    var errorMessage: String?

    var reportURL: String? {
        reportHTMLKey == nil ? nil : "/r/\(id)"
    }
}

struct CreateScanRequest: Codable, Sendable {
    let url: String
}

struct CreateScanResponse: Codable, Sendable {
    let jobID: String
    let statusURL: String
    let reportURL: String
    let pollIntervalMs: Int
}

struct ScanStatusResponse: Codable, Sendable {
    let jobID: String
    let repoURL: String
    let status: ScanJobStatus
    let createdAt: Date
    let updatedAt: Date
    let reportURL: String?
    let errorMessage: String?
    let report: ReportPayload?

    struct ReportPayload: Codable, Sendable {
        let schemaVersion: Int
        let rulesetVersion: String
        let toolVersion: String
        let generatedAt: String
        let scanComplete: Bool
        let ignoreFilesPresent: [String: Bool]
        let exposedPatterns: [[String: JSONValue]]
        let totals: [String: JSONValue]
        let errors: [String]
    }
}

/// Lightweight JSON value for forwarding report payloads without re-modeling every field.
enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension ScanStatusResponse.ReportPayload {
    static func decode(from json: String) -> Self? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
