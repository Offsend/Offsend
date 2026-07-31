import Foundation

public enum LocalStoreDirectory {
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        #if os(Linux)
        return linuxConfigDirectory(fileManager: fileManager)
        #else
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Offsend", isDirectory: true)
        #endif
    }

    private static func linuxConfigDirectory(fileManager: FileManager) -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let xdgConfigHome = environment["XDG_CONFIG_HOME"], !xdgConfigHome.isEmpty {
            return URL(fileURLWithPath: xdgConfigHome, isDirectory: true)
                .appendingPathComponent("offsend", isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/offsend", isDirectory: true)
    }
}
