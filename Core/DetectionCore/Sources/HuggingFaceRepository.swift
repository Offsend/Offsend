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
            return "\(components[0])/\(components[1])"
        }

        let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = normalized.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    public static func directoryName(for repositoryID: String) -> String {
        repositoryID.replacingOccurrences(of: "/", with: "__")
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
