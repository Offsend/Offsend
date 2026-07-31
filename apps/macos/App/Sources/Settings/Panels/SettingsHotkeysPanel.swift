import AppUIKit
import HotkeyService
import SwiftUI

struct SettingsHotkeysPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OFSettingsGroup(
                title: OffsendStrings.settingsTabHotkeys,
                hint: OffsendStrings.onboardingHotkeysSubtitle
            ) {
                OFSettingsRow(label: OffsendStrings.settingsHotkeySafePaste, hint: nil) {
                    SafePasteShortcutRecorder(title: OffsendStrings.settingsHotkeySafePaste)
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: OffsendStrings.settingsHotkeyRestorePlaceholders, hint: nil) {
                    RestorePlaceholdersShortcutRecorder(title: OffsendStrings.settingsHotkeyRestorePlaceholders)
                }
            }

            OFSettingsGroup(title: OffsendStrings.settingsHotkeysPopupSection, hint: OffsendStrings.settingsHotkeysPopupHint) {
                OFSettingsRow(label: OffsendStrings.settingsHotkeysMaskAndPaste, hint: nil) {
                    OFKeyCap(text: "↩")
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: OffsendStrings.settingsHotkeysPasteOriginal, hint: nil) {
                    HStack(spacing: 4) {
                        OFKeyCap(text: "⌥")
                        OFKeyCap(text: "↩")
                    }
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: OffsendStrings.settingsHotkeysCancel, hint: nil) {
                    OFKeyCap(text: "esc")
                }
            }

            HStack {
                Spacer()
                OFCompactButton(title: OffsendStrings.settingsResetToDefaults, variant: .ghost) {
                    coordinator.hotkeyService.resetDefaults()
                }
            }
        }
    }
}
