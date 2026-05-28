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

        Window(OffsendStrings.windowOnboarding, id: "onboarding") {
            OnboardingWindowRoot(coordinator: coordinator)
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
        guard !didRequestInitialOnboarding else { return }
        guard !coordinator.settings.hasCompletedOnboarding else { return }

        didRequestInitialOnboarding = true
        coordinator.requestOnboardingPresentation()
        openWindow(id: "onboarding")
    }

    private func configureMenuBarStatusItem() {
        coordinator.configureMenuBarStatusItem(
            openOnboarding: { openOnboardingWindow() },
            openSettings: { openWindow(id: "settings") },
            openDirectoryCheck: { openWindow(id: "directory-check") }
        )
        Task { @MainActor in
            showInitialOnboardingIfNeeded()
        }
    }

    private func openOnboardingWindow() {
        coordinator.requestOnboardingPresentation()
        openWindow(id: "onboarding")
    }
}

private struct OnboardingWindowRoot: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if shouldShowOnboardingContent {
                OnboardingView()
                    .environmentObject(coordinator)
                    .tracksDockIconWindow(using: coordinator.dockIconVisibilityService)
                    .onChange(of: coordinator.settings.hasCompletedOnboarding) { _ in
                        closeIfAlreadyCompleted()
                    }
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        dismiss()
                    }
            }
        }
    }

    private var shouldShowOnboardingContent: Bool {
        coordinator.isOnboardingPresentationRequested && !coordinator.settings.hasCompletedOnboarding
    }

    private func closeIfAlreadyCompleted() {
        guard coordinator.settings.hasCompletedOnboarding else { return }
        dismiss()
    }
}
