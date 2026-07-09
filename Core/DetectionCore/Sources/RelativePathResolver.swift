import Foundation

/// Resolves a relative path under a root directory and returns nil if it would escape
/// (absolute paths, `..` segments, home shortcuts, or symlink-assisted breakouts).
public enum RelativePathResolver {
    public static func resolvedFileURL(forRelativePath relativePath: String, in directory: URL) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") { return nil }
        if trimmed.contains("\0") { return nil }

        // Reject Windows-style absolute / drive paths that can appear in ZIP entries.
        if trimmed.contains(":\\") || trimmed.hasPrefix("\\\\") { return nil }

        let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        let components = (normalized as NSString).pathComponents
        if components.contains("..") || components.contains("~") { return nil }
        if components.contains(where: { $0.hasPrefix("/") }) { return nil }

        let root = directory.standardizedFileURL
        let candidate = root.appendingPathComponent(normalized).standardizedFileURL
        let rootPath = root.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            return nil
        }

        // Root may not exist yet (first import / CI). Lexical containment is enough then;
        // symlink checks only apply once the directory is on disk.
        guard FileManager.default.fileExists(atPath: root.path) else {
            return candidate
        }

        let resolvedRootPath = root.resolvingSymlinksInPath().path
        let resolvedAncestorPath = nearestExistingAncestor(of: candidate).resolvingSymlinksInPath().path
        guard resolvedAncestorPath == resolvedRootPath
            || resolvedAncestorPath.hasPrefix(resolvedRootPath + "/")
        else {
            return nil
        }
        return candidate
    }

    private static func nearestExistingAncestor(of url: URL) -> URL {
        var current = url.standardizedFileURL
        let fileManager = FileManager.default
        while !fileManager.fileExists(atPath: current.path) {
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
        return current
    }
}
