import Foundation
import DetectionCore

enum AIModelZipExtractor {
    /// Lists ZIP members, rejects any path that would escape `directory`, then extracts.
    static func extract(from archiveURL: URL, into directory: URL) throws {
        let entries = try listEntries(in: archiveURL)
        guard !entries.isEmpty else {
            throw AIModelCatalogError.importFailed("ZIP archive is empty.")
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for entry in entries {
            guard RelativePathResolver.resolvedFileURL(forRelativePath: entry, in: directory) != nil else {
                throw AIModelCatalogError.importFailed(
                    "ZIP entry escapes the model directory: \(entry)"
                )
            }
        }

        try runUnzip(arguments: ["-o", archiveURL.path, "-d", directory.path])

        // Belt-and-suspenders: refuse symlink breakouts that unzip may have created.
        try assertExtractedTreeStaysInside(directory)
    }

    private static func listEntries(in archiveURL: URL) throws -> [String] {
        let output = try runUnzip(arguments: ["-Z1", archiveURL.path], captureStdout: true)
        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasSuffix("/") }
    }

    @discardableResult
    private static func runUnzip(arguments: [String], captureStdout: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        if captureStdout {
            process.standardOutput = stdout
        } else {
            process.standardOutput = FileHandle.nullDevice
        }
        process.standardError = stderr

        try process.run()
        let outData = captureStdout ? stdout.fileHandleForReading.readDataToEndOfFile() : Data()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AIModelCatalogError.importFailed("Could not extract ZIP archive.")
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }

    private static func assertExtractedTreeStaysInside(_ directory: URL) throws {
        let root = directory.standardizedFileURL
        let rootPath = root.path
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        ) else {
            throw AIModelCatalogError.importFailed("Could not verify extracted ZIP contents.")
        }

        for case let itemURL as URL in enumerator {
            let standardized = itemURL.standardizedFileURL
            guard standardized.path == rootPath || standardized.path.hasPrefix(rootPath + "/") else {
                throw AIModelCatalogError.importFailed(
                    "ZIP extraction wrote outside the model directory: \(itemURL.path)"
                )
            }

            let values = try itemURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                let resolved = itemURL.resolvingSymlinksInPath()
                guard resolved.path == rootPath || resolved.path.hasPrefix(rootPath + "/") else {
                    throw AIModelCatalogError.importFailed(
                        "ZIP entry symlink escapes the model directory: \(itemURL.path)"
                    )
                }
            }
        }
    }
}
