import AppKit
import AppUIKit
import Foundation

@MainActor
final class OffsendApplicationDelegate: NSObject, NSApplicationDelegate {
    static weak var coordinator: AppCoordinator?

    func applicationWillFinishLaunching(_ notification: Notification) {
        OFSettingsChromeAppearance.migrateFromLegacyUserDefaultsIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            guard let coordinator = Self.coordinator else { return }
            for url in urls {
                coordinator.handleOffsendURL(url)
            }
        }
    }
}
