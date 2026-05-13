import AppUIKit
import SwiftUI

struct SettingsChromeThemePicker: View {
    @AppStorage(OFSettingsChromeAppearance.appStorageKey) private var chromeAppearanceRaw: String =
        OFSettingsChromeAppearance.auto.rawValue

    private var chromeAppearance: OFSettingsChromeAppearance {
        OFSettingsChromeAppearance(rawValue: chromeAppearanceRaw) ?? .auto
    }

    var body: some View {
        OFSegmentedControl(
            selection: Binding(
                get: { chromeAppearance },
                set: { chromeAppearanceRaw = $0.rawValue }
            ),
            options: [
                OFSegmentedOption(value: .light, label: OffsendStrings.settingsThemeLight),
                OFSegmentedOption(value: .dark, label: OffsendStrings.settingsThemeDark),
                OFSegmentedOption(value: .auto, label: OffsendStrings.settingsThemeAuto),
            ]
        )
    }
}
