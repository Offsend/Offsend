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

        WindowGroup(id: "directory-check", for: String.self) { $directoryPath in
            DirectoryCheckView(directoryWindowPath: directoryPath)
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
        openPresentedWindow(id: "onboarding") {
            coordinator.requestOnboardingPresentation()
        }
    }

    private func configureMenuBarStatusItem() {
        coordinator.openDirectoryCheckWindowAction = { url in
            if let url {
                openPresentedWindow(id: "directory-check", value: url.path)
            } else {
                openPresentedWindow(id: "directory-check")
            }
        }
        coordinator.configureMenuBarStatusItem(
            openOnboarding: { openOnboardingWindow() },
            openSettings: { openPresentedWindow(id: "settings") },
            openDirectoryCheck: {
                coordinator.recordDirectoryCheckOpened(source: "menu_bar")
                coordinator.openDirectoryCheckWindowAction?(nil)
            },
            openWatchedDirectoryCheck: { watchID in
                coordinator.openDirectoryCheckForWatch(watchID: watchID, source: "menu_bar")
            }
        )
        Task { @MainActor in
            showInitialOnboardingIfNeeded()
        }
    }

    private func openOnboardingWindow() {
        openPresentedWindow(id: "onboarding") {
            coordinator.requestOnboardingPresentation()
        }
    }

    private func openPresentedWindow(id: String, value: String? = nil, prepare: (() -> Void)? = nil) {
        coordinator.dockIconVisibilityService.prepareForWindowPresentation()
        prepare?()
        if let value {
            openWindow(id: id, value: value)
        } else {
            openWindow(id: id)
        }
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
        .dismissOnWindowCloseButton()
        .tracksDockIconWindow(using: coordinator.dockIconVisibilityService)
    }

    private var shouldShowOnboardingContent: Bool {
        coordinator.isOnboardingPresentationRequested && !coordinator.settings.hasCompletedOnboarding
    }

    private func closeIfAlreadyCompleted() {
        guard coordinator.settings.hasCompletedOnboarding else { return }
        dismiss()
    }
}
