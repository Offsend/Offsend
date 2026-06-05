import AnalyticsCore
import AppKit
import AppUIKit
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

        WindowGroup(OffsendStrings.windowPrepare, id: "prepare", for: String.self) { $preparePath in
            PrepareView(prepareWindowPath: preparePath)
                .environmentObject(coordinator)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: PrepareWindowChrome.windowWidth(contentWidth: PrepareWindowChrome.emptyContentWidth),
            height: PrepareWindowChrome.windowHeight(bodyHeight: 400, extraBottom: OFSpacing.md)
        )
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

        coordinator.openPrepareWindowAction = { [weak coordinator] url in
            if let url {
                coordinator?.openPresentedWindow(id: "prepare", value: url.path)
            } else {
                coordinator?.openPresentedWindow(id: "prepare")
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
            openPrepare: { [weak coordinator] in
                coordinator?.openPrepareWindow(source: "menu_bar")
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
