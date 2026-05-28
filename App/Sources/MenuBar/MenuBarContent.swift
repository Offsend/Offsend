import AppKit
import HotkeyService
import StorageCore
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var safePasteShortcut: KeyboardShortcut?
    @State private var restoreShortcut: KeyboardShortcut?

    var body: some View {
        VStack(alignment: .leading) {
            Text(OffsendStrings.appName)
                .font(.headline)

            if shouldShowOnboardingMenuItem {
                Button(OffsendStrings.menuStartOnboarding) {
                    coordinator.requestOnboardingPresentation()
                    openWindow(id: "onboarding")
                }
                Divider()
            }

            Button(OffsendStrings.menuSafePaste) {
                coordinator.performSafePaste()
            }
            .optionalKeyboardShortcut(safePasteShortcut)

            Button(OffsendStrings.menuRestorePlaceholders) {
                coordinator.restorePlaceholders()
            }
            .optionalKeyboardShortcut(restoreShortcut)

            Divider()

            Toggle(OffsendStrings.menuProtection(coordinator.settings.protectionEnabled ? OffsendStrings.commonOn : OffsendStrings.commonOff), isOn: binding(\.protectionEnabled))
            Toggle(OffsendStrings.menuClipboardMonitoring(coordinator.settings.clipboardMonitoringEnabled ? OffsendStrings.commonOn : OffsendStrings.commonOff), isOn: binding(\.clipboardMonitoringEnabled))

            Divider()

            Button(OffsendStrings.menuCheckDirectory) { openWindow(id: "directory-check") }
            Button(OffsendStrings.menuOpenSettings) { openWindow(id: "settings") }
            Button(OffsendStrings.menuCheckForUpdates) {
                coordinator.checkForSparkleUpdates(sender: nil)
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
        .onAppear(perform: refreshShortcuts)
        .onReceive(NotificationCenter.default.publisher(for: .keyboardShortcutDidChange)) { _ in
            refreshShortcuts()
        }
    }

    private func refreshShortcuts() {
        safePasteShortcut = HotkeyDisplay.swiftUIKeyboardShortcut(for: .safePaste)
        restoreShortcut = HotkeyDisplay.swiftUIKeyboardShortcut(for: .restorePlaceholders)
    }

    private var shouldShowOnboardingMenuItem: Bool {
        #if DEBUG
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

private extension View {
    @ViewBuilder
    func optionalKeyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut {
            self.keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}
