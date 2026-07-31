import StorageCore
import SwiftUI

@MainActor
struct SettingsCoordinatorBinder {
    var coordinator: AppCoordinator

    func setting<Value: Sendable>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    coordinator.settings[keyPath: keyPath]
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    coordinator.settings[keyPath: keyPath] = newValue
                    coordinator.saveSettings()
                }
            }
        )
    }
}
