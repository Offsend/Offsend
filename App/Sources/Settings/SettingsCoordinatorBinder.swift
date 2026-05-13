import StorageCore
import SwiftUI

struct SettingsCoordinatorBinder {
    var coordinator: AppCoordinator

    func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { coordinator.settings[keyPath: keyPath] },
            set: {
                coordinator.settings[keyPath: keyPath] = $0
                coordinator.saveSettings()
            }
        )
    }
}
