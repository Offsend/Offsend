import AnalyticsCore
import AppKit
import SwiftUI

@main
struct OffsendApp: App {
    @NSApplicationDelegateAdaptor(OffsendApplicationDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator

    init() {
        TelemetryDeckBootstrap.initializeIfConfigured()
        _coordinator = StateObject(wrappedValue: AppCoordinator())
    }
    @State private var didRequestInitialOnboarding = false
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        let _ = configureMenuBarStatusItem()

        WindowGroup(OffsendStrings.windowOnboarding, id: "onboarding") {
            OnboardingView()
                .environmentObject(coordinator)
                .tracksDockIconWindow(using: coordinator.dockIconVisibilityService)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window(OffsendStrings.windowSettings, id: "settings") {
            SettingsView()
                .environmentObject(coordinator)
                .tracksDockIconWindow(using: coordinator.dockIconVisibilityService)
        }
        .defaultSize(width: 760, height: 560)

        WindowGroup(OffsendStrings.windowLocalMappings, id: "mappings") {
            LocalMappingsView()
                .environmentObject(coordinator)
                .tracksDockIconWindow(using: coordinator.dockIconVisibilityService)
        }
        .defaultSize(width: 560, height: 420)

        WindowGroup(OffsendStrings.windowDirectoryCheck, id: "directory-check") {
            DirectoryCheckView()
                .environmentObject(coordinator)
                .tracksDockIconWindow(using: coordinator.dockIconVisibilityService)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentSize)
    }

    private func showInitialOnboardingIfNeeded() {
        guard !didRequestInitialOnboarding, !coordinator.settings.hasCompletedOnboarding else {
            return
        }

        didRequestInitialOnboarding = true
        openWindow(id: "onboarding")
    }

    private func configureMenuBarStatusItem() {
        coordinator.configureMenuBarStatusItem(
            openOnboarding: { openWindow(id: "onboarding") },
            openSettings: { openWindow(id: "settings") },
            openDirectoryCheck: { openWindow(id: "directory-check") }
        )
        Task { @MainActor in
            showInitialOnboardingIfNeeded()
        }
    }
}
