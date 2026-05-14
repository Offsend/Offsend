import AppKit
import StorageCore
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading) {
            Text(OffsendStrings.appName)
                .font(.headline)

            if shouldShowOnboardingMenuItem {
                Button(OffsendStrings.menuStartOnboarding) {
                    openWindow(id: "onboarding")
                }
                Divider()
            }

            Button(OffsendStrings.menuSafePaste) {
                coordinator.performSafePaste()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button(OffsendStrings.menuRestorePlaceholders) {
                coordinator.restorePlaceholders()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Toggle(OffsendStrings.menuProtection(coordinator.settings.protectionEnabled ? OffsendStrings.commonOn : OffsendStrings.commonOff), isOn: binding(\.protectionEnabled))
            Toggle(OffsendStrings.menuClipboardMonitoring(coordinator.settings.clipboardMonitoringEnabled ? OffsendStrings.commonOn : OffsendStrings.commonOff), isOn: binding(\.clipboardMonitoringEnabled))

            Divider()

            Button(OffsendStrings.menuOpenSettings) { openWindow(id: "settings") }
            Button(OffsendStrings.menuCheckForUpdates) {
                coordinator.lastStatusMessage = OffsendStrings.statusSparkleReleaseBuilds
            }

            Divider()

            Text(coordinator.lastStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(OffsendStrings.menuQuit) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }

    private var shouldShowOnboardingMenuItem: Bool {
        #if OFFSEND_INTERNAL
        true
        #else
        !coordinator.settings.hasCompletedOnboarding
        #endif
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { coordinator.settings[keyPath: keyPath] },
            set: {
                coordinator.settings[keyPath: keyPath] = $0
                coordinator.saveSettings()
            }
        )
    }
}
