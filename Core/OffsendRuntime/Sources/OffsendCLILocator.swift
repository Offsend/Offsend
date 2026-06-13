import Foundation

public enum OffsendCLILocator {
    public static let managedHookMarker = "# offsend-managed"
    public static let managedHookVersion = "v1"

    public static func resolvedExecutablePath(
        invokedPath: String? = ProcessInfo.processInfo.arguments.first,
        fileManager: FileManager = .default
    ) -> String? {
        // Keep the invoked path as-is (without resolving symlinks) so that a
        // stable path like /opt/homebrew/bin/offsend is preferred over a
        // version-specific Cellar path that breaks on upgrade.
        if let invokedPath, invokedPath.contains("/") {
            let absolute = URL(fileURLWithPath: invokedPath).standardizedFileURL.path
            if !isAppBundleMainExecutablePath(absolute),
               fileManager.isExecutableFile(atPath: absolute) {
                return absolute
            }
        }

        let bundledInMainApp = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/offsend")
            .path
        if fileManager.isExecutableFile(atPath: bundledInMainApp) {
            return bundledInMainApp
        }

        let bundleCandidates = [
            "/Applications/Offsend.app/Contents/Helpers/offsend",
            "\(NSHomeDirectory())/Applications/Offsend.app/Contents/Helpers/offsend"
        ]
        for candidate in bundleCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return which("offsend", fileManager: fileManager)
    }

    static func isAppBundleMainExecutablePath(_ path: String) -> Bool {
        path.contains(".app/Contents/MacOS/")
    }

    private static func which(_ command: String, fileManager: FileManager) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty, fileManager.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }
}
