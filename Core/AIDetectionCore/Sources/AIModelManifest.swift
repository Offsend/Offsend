import Foundation
import CryptoKit
import DetectionCore

public struct AIModelManifest: Codable, Equatable, Sendable {
    public struct FileEntry: Codable, Equatable, Sendable {
        public let url: URL
        public let path: String

        public init(url: URL, path: String) {
            self.url = url
            self.path = path
        }
    }

    public let id: String
    public let displayName: String
    public let format: AIModelFormat
    public let files: [FileEntry]
    public let sha256: [String: String]?

    public init(
        id: String,
        displayName: String,
        format: AIModelFormat,
        files: [FileEntry],
        sha256: [String: String]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.format = format
        self.files = files
        self.sha256 = sha256
    }
}

public enum AIModelManifestParser {
    public static func parse(data: Data) throws -> AIModelManifest {
        let decoder = JSONDecoder()
        return try decoder.decode(AIModelManifest.self, from: data)
    }
}

public enum AIModelChecksumValidator {
    /// Streaming SHA-256 so multi-gigabyte model files are never loaded into memory at once.
    public static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func validate(
        directory: URL,
        expected: [String: String]
    ) -> [String] {
        var warnings: [String] = []
        for (relativePath, expectedHash) in expected {
            let fileURL = directory.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                warnings.append("Missing file for checksum: \(relativePath)")
                continue
            }
            guard let actual = try? sha256(of: fileURL) else {
                warnings.append("Could not compute checksum for \(relativePath)")
                continue
            }
            if actual.lowercased() != expectedHash.lowercased() {
                warnings.append("Checksum mismatch for \(relativePath)")
            }
        }
        return warnings
    }
}
