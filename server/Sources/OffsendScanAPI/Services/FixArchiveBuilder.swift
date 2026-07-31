import Foundation

/// Reads ready-to-use AI ignore files from a Check report's `fixFiles` array.
enum FixArchiveBuilder {
    /// One file the user should create to resolve findings: its repo-relative path
    /// and full ready-to-use contents.
    struct FixFile: Sendable, Equatable, Encodable {
        let path: String
        let contents: String
    }

    private struct Payload: Decodable {
        let fixFiles: [FixFileDTO]?

        struct FixFileDTO: Decodable {
            let path: String
            let contents: String
        }
    }

    /// The files a user should create to pass the scan, or an empty array when there
    /// is nothing to fix / the report has no `fixFiles`.
    static func fixFiles(reportJSON: String) -> [FixFile] {
        guard let data = reportJSON.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let files = payload.fixFiles
        else {
            return []
        }
        return files.map { FixFile(path: $0.path, contents: $0.contents) }
    }
}
