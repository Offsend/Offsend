import Foundation

enum RepositoryURLError: Error, Sendable, LocalizedError {
    case empty
    case unsupportedHost(String)
    case invalidURL(String)
    case pathNotAllowed

    var errorDescription: String? {
        switch self {
        case .empty:
            "Repository URL is required."
        case let .unsupportedHost(host):
            "Unsupported git host: \(host). Only public GitHub, GitLab, and Bitbucket HTTPS URLs are supported."
        case let .invalidURL(value):
            "Invalid repository URL: \(value)"
        case .pathNotAllowed:
            "Repository URL must point to a repository root, not a file or subdirectory."
        }
    }
}

enum RepositoryURLValidator {
    private static let allowedHosts: Set<String> = [
        "github.com",
        "www.github.com",
        "gitlab.com",
        "www.gitlab.com",
        "bitbucket.org",
        "www.bitbucket.org",
    ]

    /// Normalizes supported public git HTTPS URLs for shallow clone.
    static func normalize(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryURLError.empty }

        var candidate = trimmed
        if !candidate.contains("://") {
            if candidate.hasPrefix("git@github.com:") {
                let path = String(candidate.dropFirst("git@github.com:".count))
                candidate = "https://github.com/\(path)"
            } else {
                candidate = "https://\(candidate)"
            }
        }

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              let host = components.host?.lowercased(),
              allowedHosts.contains(host),
              components.port == nil,
              let url = components.url else {
            throw RepositoryURLError.invalidURL(trimmed)
        }

        components.user = nil
        components.password = nil
        components.fragment = nil
        components.query = nil

        var path = components.path
        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments = path.split(separator: "/").map(String.init)
        guard segments.count == 2, !segments[0].isEmpty, !segments[1].isEmpty else {
            throw RepositoryURLError.pathNotAllowed
        }
        if segments.contains(where: { $0 == ".." || $0 == "." }) {
            throw RepositoryURLError.invalidURL(trimmed)
        }

        components.path = "/\(segments[0])/\(segments[1])"
        guard let normalized = components.url else {
            throw RepositoryURLError.invalidURL(trimmed)
        }
        return normalized
    }

    static func cloneURL(for normalized: URL) -> URL {
        normalized.appendingPathExtension("git")
    }
}
