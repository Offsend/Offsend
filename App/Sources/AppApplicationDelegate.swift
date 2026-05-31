import AppKit
import Foundation
import UserNotifications

@MainActor
final class OffsendApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            guard let coordinator = Self.coordinator else { return }
            for url in urls {
                coordinator.handleOffsendURL(url)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            Self.coordinator?.handleWorkspaceWatchNotificationResponse(response)
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
