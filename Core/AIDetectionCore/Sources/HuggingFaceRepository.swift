import Foundation

public enum HuggingFaceRepository {
    public static let host = "huggingface.co"

    /// Normalizes user input to `author/model` or returns nil.
    public static func parseRepositoryID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let urlHost = url.host?.lowercased(), urlHost.contains(Self.host) {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = path.split(separator: "/").map(String.init)
            guard components.count >= 2 else { return nil }
            if components[0] == "datasets" || components[0] == "spaces" {
                return nil
            }
            return sanitizedRepositoryID(author: components[0], model: components[1])
        }

        let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = normalized.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return sanitizedRepositoryID(author: parts[0], model: parts[1])
    }

    public static func directoryName(for repositoryID: String) -> String {
        repositoryID.replacingOccurrences(of: "/", with: "__")
    }

    private static func sanitizedRepositoryID(author: String, model: String) -> String? {
        guard isSafeRepositoryComponent(author), isSafeRepositoryComponent(model) else { return nil }
        return "\(author)/\(model)"
    }

    private static func isSafeRepositoryComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != "..", !value.contains("..") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public static func resolveURL(
        repositoryID: String,
        revision: String,
        relativePath: String
    ) -> URL? {
        var encodedPath = ""
        for component in relativePath.split(separator: "/") {
            encodedPath.append("/\(component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component))")
        }
        return URL(string: "https://\(host)/\(repositoryID)/resolve/\(revision)\(encodedPath)")
    }

    public static func treeAPIURL(repositoryID: String, revision: String, path: String = "") -> URL? {
        var urlString = "https://\(host)/api/models/\(repositoryID)/tree/\(revision)"
        if !path.isEmpty {
            let encoded = path.split(separator: "/")
                .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                .joined(separator: "/")
            urlString += "/\(encoded)"
        }
        return URL(string: urlString)
    }

    public static func modelAPIURL(repositoryID: String) -> URL? {
        URL(string: "https://\(host)/api/models/\(repositoryID)")
    }
}
