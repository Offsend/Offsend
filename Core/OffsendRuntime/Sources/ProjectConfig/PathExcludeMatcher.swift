#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

public enum PathExcludeMatcher {
    public static func isExcluded(relativePath: String, patterns: [String]) -> Bool {
        let normalized = normalize(relativePath)
        guard !normalized.isEmpty else { return false }
        return patterns.contains { pattern in
            matches(pattern: pattern, relativePath: normalized)
        }
    }

    /// Whether an entire directory tree can be skipped during enumeration.
    public static func shouldSkipDirectory(relativePath: String, patterns: [String]) -> Bool {
        let normalized = normalize(relativePath)
        if normalized.isEmpty { return false }
        if normalized == ".git" || normalized.hasSuffix("/.git") {
            return true
        }
        // A directory is skippable when the directory path itself is excluded
        // (e.g. `node_modules/**` matches `node_modules`).
        return isExcluded(relativePath: normalized, patterns: patterns)
    }

    public static func relativePath(of fileURL: URL, relativeTo workingDirectory: URL) -> String {
        let workingPath = workingDirectory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(workingPath + "/") {
            return String(filePath.dropFirst(workingPath.count + 1))
        }
        if filePath == workingPath {
            return ""
        }
        return fileURL.lastPathComponent
    }

    public static func filter(
        fileURLs: [URL],
        excludePatterns: [String],
        workingDirectory: URL
    ) -> [URL] {
        guard !excludePatterns.isEmpty else { return fileURLs }

        return fileURLs.filter { fileURL in
            let relative = relativePath(of: fileURL, relativeTo: workingDirectory)
            return !isExcluded(relativePath: relative, patterns: excludePatterns)
        }
    }

    private static func normalize(_ relativePath: String) -> String {
        var path = relativePath.replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("./") {
            path = String(path.dropFirst(2))
        }
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }
        return path
    }

    private static func matches(pattern: String, relativePath: String) -> Bool {
        if pattern.hasSuffix("/**") {
            let body = String(pattern.dropLast(3))
            return matchesDirectoryTree(body: body, relativePath: relativePath)
        }

        if pattern.contains("/") {
            return fnmatch(pattern, relativePath, FNM_PATHNAME) == 0
        }

        if let slash = relativePath.lastIndex(of: "/") {
            let fileName = String(relativePath[relativePath.index(after: slash)...])
            return fnmatch(pattern, fileName, 0) == 0
                || fnmatch(pattern, relativePath, FNM_PATHNAME) == 0
        }

        return fnmatch(pattern, relativePath, 0) == 0
    }

    /// Patterns like `vendor/**`, `**/build/**`, `*.egg-info/**`, `**/node_modules/**`.
    private static func matchesDirectoryTree(body: String, relativePath: String) -> Bool {
        if body.hasPrefix("**/") {
            let rest = String(body.dropFirst(3))
            return pathHasMatchingSegment(relativePath, segmentPattern: rest)
        }

        if body.contains("*") || body.contains("?") || body.contains("[") {
            return pathHasMatchingSegment(relativePath, segmentPattern: body)
        }

        return relativePath == body || relativePath.hasPrefix(body + "/")
    }

    /// True when any path segment matches `segmentPattern`, or the path is under such a segment.
    private static func pathHasMatchingSegment(_ relativePath: String, segmentPattern: String) -> Bool {
        let segments = relativePath.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return false }

        if segmentPattern.contains("/") {
            // Rare: `**/foo/bar/**` → body after **/ is `foo/bar`
            return relativePath == segmentPattern
                || relativePath.hasPrefix(segmentPattern + "/")
                || relativePath.contains("/" + segmentPattern + "/")
                || relativePath.hasSuffix("/" + segmentPattern)
        }

        for segment in segments {
            if fnmatch(segmentPattern, segment, 0) == 0 {
                return true
            }
        }
        return false
    }
}
