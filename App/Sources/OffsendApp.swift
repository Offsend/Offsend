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
        }
        .defaultSize(width: 760, height: 560)

        WindowGroup(OffsendStrings.windowLocalMappings, id: "mappings") {
            LocalMappingsView()
                .environmentObject(coordinator)
        }
        .defaultSize(width: 560, height: 420)

        WindowGroup(id: "directory-check", for: String.self) { $directoryPath in
            DirectoryCheckView(directoryWindowPath: directoryPath)
                .environmentObject(coordinator)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentSize)

        WindowGroup(OffsendStrings.windowDocumentSanitize, id: "document-sanitize", for: String.self) { $documentPath in
            DocumentSanitizeView(documentWindowPath: documentPath)
                .environmentObject(coordinator)
        }
        .defaultSize(width: 640, height: 392)
        .windowResizability(.contentSize)
    }

    private func showInitialOnboardingIfNeeded() {
        guard !didRequestInitialOnboarding else { return }
        guard !coordinator.settings.hasCompletedOnboarding else { return }

        didRequestInitialOnboarding = true
        coordinator.openPresentedWindow(id: "onboarding") { [weak coordinator] in
            coordinator?.requestOnboardingPresentation()
        }
    }

    private func configureMenuBarStatusItem() {
        coordinator.presentWindowAction = { id, value in
            if let value {
                openWindow(id: id, value: value)
            } else {
                openWindow(id: id)
            }
        }

        coordinator.openDirectoryCheckWindowAction = { [weak coordinator] url in
            if let url {
                coordinator?.openPresentedWindow(id: "directory-check", value: url.path)
            } else {
                coordinator?.openPresentedWindow(id: "directory-check")
            }
        }
        coordinator.openDocumentSanitizeWindowAction = { [weak coordinator] url in
            if let url {
                coordinator?.openPresentedWindow(id: "document-sanitize", value: url.path)
            } else {
                coordinator?.openPresentedWindow(id: "document-sanitize")
            }
        }
        coordinator.configureMenuBarStatusItem(
            openOnboarding: { [weak coordinator] in
                coordinator?.openPresentedWindow(id: "onboarding") {
                    coordinator?.requestOnboardingPresentation()
                }
            },
            openSettings: { [weak coordinator] in
                coordinator?.openPresentedWindow(id: "settings")
            },
            openDirectoryCheck: { [weak coordinator] in
                coordinator?.recordDirectoryCheckOpened(source: "menu_bar")
                coordinator?.openDirectoryCheckWindowAction?(nil)
            },
            openDocumentSanitize: { [weak coordinator] in
                coordinator?.recordDocumentSanitizeOpened(source: "menu_bar")
                coordinator?.openDocumentSanitizeWindowAction?(nil)
            },
            openWatchedDirectoryCheck: { [weak coordinator] watchID in
                coordinator?.openDirectoryCheckForWatch(watchID: watchID, source: "menu_bar")
            }
        )
        Task { @MainActor in
            showInitialOnboardingIfNeeded()
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
    }

    private var shouldShowOnboardingContent: Bool {
        coordinator.isOnboardingPresentationRequested && !coordinator.settings.hasCompletedOnboarding
    }

    private func closeIfAlreadyCompleted() {
        guard coordinator.settings.hasCompletedOnboarding else { return }
        dismiss()
    }
}
