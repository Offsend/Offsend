import AppKit
import AppUIKit
import StorageCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsGeneralPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    var body: some View {
        let binder = SettingsCoordinatorBinder(coordinator: coordinator)
        VStack(alignment: .leading, spacing: 0) {
            statusCard(binder: binder)
                .padding(.bottom, 22)

            OFSettingsGroup(title: OffsendStrings.settingsGeneralSectionStartup) {
                OFSettingsRow(label: OffsendStrings.settingsLaunchAtLogin, hint: nil) {
                    OFToggle(isOn: binder.setting(\.launchAtLogin))
                }
                OFSettingsGroupDivider()
                OFSettingsRow(label: OffsendStrings.settingsMonitorClipboardChanges, hint: nil) {
                    OFToggle(isOn: binder.setting(\.clipboardMonitoringEnabled))
                }
            }

            if coordinator.settings.clipboardMonitoringEnabled {
                excludedAppsSection(binder: binder)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            OFSettingsGroup(title: OffsendStrings.settingsGeneralSectionBehavior) {
                OFSettingsRow(label: OffsendStrings.settingsDefaultActionNoRisk, hint: nil) {
                    OFSelectMenu(
                        selection: binder.setting(\.defaultNoRiskAction),
                        options: DefaultNoRiskAction.allCases.map {
                            OFSelectOption(value: $0, label: AppLocalization.defaultNoRiskActionName($0))
                        }
                    )
                }
            }

            OFSettingsGroup(title: OffsendStrings.settingsGeneralSectionAppearance, hint: OffsendStrings.settingsGeneralThemeHint) {
                OFSettingsRow(
                    label: "\(OffsendStrings.settingsThemeLight) · \(OffsendStrings.settingsThemeDark) · \(OffsendStrings.settingsThemeAuto)",
                    hint: nil
                ) {
                    SettingsChromeThemePicker()
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: coordinator.settings.clipboardMonitoringEnabled)
    }

    private func statusCard(binder: SettingsCoordinatorBinder) -> some View {
        let on = coordinator.settings.protectionEnabled
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(on ? palette.green.opacity(0.18) : palette.textMuted.opacity(0.12))
                    .frame(width: 30, height: 30)
                Circle()
                    .fill(on ? palette.green : palette.textMuted)
                    .frame(width: 14, height: 14)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(on ? OffsendStrings.settingsGeneralStatusOnTitle : OffsendStrings.settingsGeneralStatusOffTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.text)
                Text(
                    on
                        ? OffsendStrings.settingsGeneralStatusOnSubtitle
                        : OffsendStrings.settingsGeneralStatusOffSubtitle
                )
                .font(.system(size: 11.5))
                .foregroundColor(palette.textSub)
                if !coordinator.lastStatusMessage.isEmpty, coordinator.lastStatusMessage != OffsendStrings.statusReady {
                    Text(coordinator.lastStatusMessage)
                        .font(.system(size: 10.5))
                        .foregroundColor(palette.textMuted)
                        .padding(.top, 2)
                }
            }
            Spacer()
            OFToggle(isOn: binder.setting(\.protectionEnabled))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(on ? palette.green.opacity(0.10) : palette.bg2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(on ? palette.green.opacity(0.20) : palette.border, lineWidth: 1)
                )
        )
    }

    private func excludedAppsSection(binder _: SettingsCoordinatorBinder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(OffsendStrings.settingsGeneralExcludedHeading.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(palette.textMuted)
                Spacer()
                Text(
                    OffsendStrings.settingsGeneralExcludedCount(coordinator.settings.excludedClipboardApplications.count)
                )
                .font(.system(size: 11))
                .foregroundColor(palette.textMuted)
            }
            .padding(.leading, 2)

            Text(OffsendStrings.settingsExcludedAppsDescription)
                .font(.system(size: 12))
                .foregroundColor(palette.textSub)
                .padding(.leading, 2)
                .frame(maxWidth: 520, alignment: .leading)

            VStack(spacing: 0) {
                if coordinator.settings.excludedClipboardApplications.isEmpty {
                    Text(OffsendStrings.settingsGeneralExcludedEmpty)
                        .font(.system(size: 12))
                        .foregroundColor(palette.textSub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                } else {
                    ForEach(Array(coordinator.settings.excludedClipboardApplications.enumerated()), id: \.element.id) { idx, app in
                        HStack(spacing: 12) {
                            OFAppTile(name: app.displayName)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.displayName)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundColor(palette.text)
                                Text(app.bundleIdentifier)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(palette.textMuted)
                            }
                            Spacer()
                            Button {
                                removeExcludedApplication(app)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(palette.textMuted)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        if idx < coordinator.settings.excludedClipboardApplications.count - 1 {
                            OFSettingsGroupDivider()
                        }
                    }
                }

                Rectangle()
                    .fill(palette.border)
                    .frame(height: coordinator.settings.excludedClipboardApplications.isEmpty ? 0 : 1)

                Button {
                    addExcludedApplication()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text(OffsendStrings.settingsGeneralAddAppExclude)
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .foregroundColor(palette.textSub)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
            )
        }
        .padding(.bottom, 24)
    }

    private func addExcludedApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else { return }
        guard !coordinator.settings.excludedClipboardApplications.contains(where: {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }) else { return }

        let displayName =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
        coordinator.settings.excludedClipboardApplications.append(
            ExcludedClipboardApplication(displayName: displayName, bundleIdentifier: bundleIdentifier)
        )
        coordinator.saveSettings()
    }

    private func removeExcludedApplication(_ application: ExcludedClipboardApplication) {
        coordinator.settings.excludedClipboardApplications.removeAll {
            $0.bundleIdentifier.caseInsensitiveCompare(application.bundleIdentifier) == .orderedSame
        }
        coordinator.saveSettings()
    }
}
