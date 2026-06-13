import Darwin
import Foundation

public enum PathExcludeMatcher {
    public static func isExcluded(relativePath: String, patterns: [String]) -> Bool {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        return patterns.contains { pattern in
            matches(pattern: pattern, relativePath: normalized)
        }
    }

    public static func filter(
        fileURLs: [URL],
        excludePatterns: [String],
        workingDirectory: URL
    ) -> [URL] {
        guard !excludePatterns.isEmpty else { return fileURLs }

        let workingPath = workingDirectory.standardizedFileURL.path
        return fileURLs.filter { fileURL in
            let filePath = fileURL.standardizedFileURL.path
            let relative: String
            if filePath.hasPrefix(workingPath + "/") {
                relative = String(filePath.dropFirst(workingPath.count + 1))
            } else {
                relative = fileURL.lastPathComponent
            }
            return !isExcluded(relativePath: relative, patterns: excludePatterns)
        }
    }

    private static func matches(pattern: String, relativePath: String) -> Bool {
        if pattern.hasSuffix("/**") {
            let prefix = String(pattern.dropLast(3))
            return relativePath == prefix || relativePath.hasPrefix(prefix + "/")
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
}
