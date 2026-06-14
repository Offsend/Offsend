import AppKit
import AppUIKit
import OffsendRuntime
import StorageCore
import SwiftUI

private enum HookFailPolicyOption: String, CaseIterable, Hashable, Identifiable {
    case block
    case warn
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .block:
            return OffsendStrings.settingsHooksFailPolicyBlock
        case .warn:
            return OffsendStrings.settingsHooksFailPolicyWarn
        case .none:
            return OffsendStrings.settingsHooksFailPolicyNone
        }
    }
}

struct SettingsHooksPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryCard
                .padding(.bottom, 22)

            repositoriesSection
                .padding(.bottom, 24)

            cliSection
        }
        .onAppear {
            coordinator.refreshHookedRepositoryStatuses()
        }
    }

    private var summaryCard: some View {
        let repositories = coordinator.settings.hookedRepositories
        let installedCount = repositories.filter {
            coordinator.displayStatus(for: $0) == .installed
        }.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(palette.blueDim)
                    Image(systemName: "terminal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.blue)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(OffsendStrings.settingsHooksSummaryTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.text)
                    Text(OffsendStrings.settingsHooksSummarySubtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                OFCompactButton(
                    title: OffsendStrings.settingsHooksAddProject,
                    icon: "plus",
                    variant: .primary
                ) {
                    addRepository()
                }
            }

            HStack(alignment: .top, spacing: 10) {
                OFStatTile(
                    icon: "folder",
                    label: OffsendStrings.settingsHooksStatProjects,
                    value: "\(repositories.count)",
                    accessory: .none
                )
                OFStatTile(
                    icon: "link",
                    label: OffsendStrings.settingsHooksStatInstalled,
                    value: "\(installedCount)",
                    accessory: .none
                )
                OFStatTile(
                    icon: "terminal",
                    label: OffsendStrings.settingsHooksStatCli,
                    value: coordinator.offsendCLIExecutablePath == nil
                        ? OffsendStrings.settingsHooksCliMissingShort
                        : OffsendStrings.settingsHooksCliReadyShort,
                    accessory: cliAccessory
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [palette.blueDim, palette.card],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border, lineWidth: 1))
        )
    }

    private var cliAccessory: OFStatTileAccessory {
        coordinator.offsendCLIExecutablePath == nil
            ? .caption(OffsendStrings.settingsHooksCliMissingHint)
            : .caption(OffsendStrings.settingsHooksCliReadyHint)
    }

    private var repositoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(OffsendStrings.settingsHooksSectionProjects.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(palette.textMuted)
                .padding(.leading, 2)

            if coordinator.settings.hookedRepositories.isEmpty {
                Text(OffsendStrings.settingsHooksEmptyState)
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSub)
                    .padding(.leading, 2)
                    .frame(maxWidth: 520, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(coordinator.settings.hookedRepositories) { entry in
                        repositoryRow(entry)
                        if entry.id != coordinator.settings.hookedRepositories.last?.id {
                            OFSettingsGroupDivider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(palette.card)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
                )
                .padding(.bottom, 24)
            }
        }
    }

    private func repositoryRow(_ entry: HookedRepository) -> some View {
        let current = coordinator.settings.hookedRepositories.first(where: { $0.id == entry.id }) ?? entry
        let status = coordinator.displayStatus(for: current)
        let path = current.resolvedPath ?? current.displayName ?? OffsendStrings.settingsHooksUnknownPath

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.displayName ?? URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.text)
                    Text(path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(palette.textMuted)
                        .lineLimit(2)
                    if coordinator.projectConfigPath(for: current) != nil {
                        Text(OffsendStrings.settingsHooksProjectConfigFound)
                            .font(.system(size: 10.5))
                            .foregroundColor(palette.blue)
                    }
                }
                Spacer(minLength: 8)
                hookStatusBadge(status)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(OffsendStrings.settingsHooksPolicyCheckLabel)
                        .font(.system(size: 12))
                        .foregroundColor(palette.text)
                    Text(OffsendStrings.settingsHooksPolicyCheckHint)
                        .font(.system(size: 10.5))
                        .foregroundColor(palette.textMuted)
                }
                Spacer()
                OFToggle(
                    isOn: Binding(
                        get: {
                            coordinator.settings.hookedRepositories.first(where: { $0.id == entry.id })?.includePolicyCheck ?? false
                        },
                        set: { coordinator.updateHookedRepositoryPolicy(id: entry.id, includePolicyCheck: $0) }
                    )
                )
            }

            HStack(spacing: 10) {
                Text(OffsendStrings.settingsHooksFailPolicyLabel)
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSub)
                OFSelectMenu(
                    selection: Binding(
                        get: {
                            let policy = coordinator.settings.hookedRepositories.first(where: { $0.id == entry.id })?.failPolicy ?? "block"
                            return HookFailPolicyOption(rawValue: policy) ?? .block
                        },
                        set: { coordinator.updateHookedRepositoryFailPolicy(id: entry.id, failPolicy: CheckFailPolicy(rawValue: $0.rawValue) ?? .block) }
                    ),
                    options: HookFailPolicyOption.allCases.map {
                        OFSelectOption(value: $0, label: $0.title)
                    }
                )
                Spacer()
            }

            HStack(spacing: 8) {
                switch status {
                case .installed:
                    OFCompactButton(
                        title: OffsendStrings.settingsHooksReinstall,
                        icon: "arrow.clockwise",
                        variant: .outline
                    ) {
                        _ = coordinator.installHook(for: entry.id, force: true)
                    }
                    OFCompactButton(
                        title: OffsendStrings.settingsHooksUninstall,
                        icon: "trash",
                        variant: .outline
                    ) {
                        _ = coordinator.uninstallHook(for: entry.id)
                    }
                case .modified:
                    OFCompactButton(
                        title: OffsendStrings.settingsHooksReinstall,
                        icon: "arrow.clockwise",
                        variant: .primary
                    ) {
                        _ = coordinator.installHook(for: entry.id, force: true)
                    }
                default:
                    OFCompactButton(
                        title: OffsendStrings.settingsHooksInstall,
                        icon: "link.badge.plus",
                        variant: .primary
                    ) {
                        _ = coordinator.installHook(for: entry.id)
                    }
                }

                OFCompactButton(
                    title: OffsendStrings.settingsHooksOpenFinder,
                    icon: "folder",
                    variant: .outline
                ) {
                    coordinator.openHookedRepositoryInFinder(id: entry.id)
                }

                OFCompactButton(
                    title: OffsendStrings.settingsHooksCopyCommand,
                    icon: "doc.on.doc",
                    variant: .outline
                ) {
                    coordinator.copyHookedRepositoryInstallCommand(for: entry)
                }

                Spacer()

                Button {
                    coordinator.removeHookedRepository(id: entry.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(palette.textMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func hookStatusBadge(_ status: HookedRepositoryDisplayStatus) -> some View {
        let title: String
        let textColor: Color
        let bgColor: Color

        switch status {
        case .installed:
            title = OffsendStrings.settingsHooksStatusInstalled
            textColor = palette.greenText
            bgColor = palette.greenDim
        case .missing:
            title = OffsendStrings.settingsHooksStatusMissing
            textColor = palette.textMuted
            bgColor = palette.bg3
        case .modified:
            title = OffsendStrings.settingsHooksStatusModified
            textColor = palette.amberText
            bgColor = palette.amberDim
        case .unavailable:
            title = OffsendStrings.settingsHooksStatusUnavailable
            textColor = palette.redText
            bgColor = palette.redDim
        }

        return Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgColor)
            .cornerRadius(4)
    }

    private var cliSection: some View {
        let pathStatus = coordinator.cliPathInstallationStatus

        return OFSettingsGroup(
            title: OffsendStrings.settingsHooksSectionCli,
            hint: OffsendStrings.settingsHooksSectionCliHint
        ) {
            OFSettingsRow(
                label: OffsendStrings.settingsHooksCliPathLabel,
                hint: nil,
                alignTop: true
            ) {
                Text(coordinator.offsendCLIExecutablePath ?? OffsendStrings.settingsHooksCliMissingPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(palette.textSub)
                    .frame(maxWidth: 360, alignment: .leading)
                    .textSelection(.enabled)
            }

            OFSettingsGroupDivider()

            OFSettingsRow(
                label: OffsendStrings.settingsHooksCliPathCommandLabel,
                hint: cliPathStatusHint(pathStatus),
                alignTop: true
            ) {
                VStack(alignment: .trailing, spacing: 7) {
                    cliPathStatusBadge(pathStatus.state)
                    Text(pathStatus.commandPath ?? pathStatus.installPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(palette.textMuted)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 360, alignment: .trailing)
            }

            OFSettingsGroupDivider()

            HStack(spacing: 8) {
                switch pathStatus.state {
                case .installed:
                    OFCompactButton(
                        title: OffsendStrings.settingsHooksCliPathUninstall,
                        icon: "trash",
                        variant: .outline
                    ) {
                        coordinator.uninstallCLICommandFromPath()
                    }
                case .notInstalled, .brokenManagedLink:
                    OFCompactButton(
                        title: OffsendStrings.settingsHooksCliPathInstall,
                        icon: "terminal",
                        variant: .primary
                    ) {
                        coordinator.installCLICommandInPath()
                    }
                case .availableViaHomebrew:
                    OFCompactButton(
                        title: OffsendStrings.settingsHooksCliPathCopyBrewUninstall,
                        icon: "doc.on.doc",
                        variant: .outline
                    ) {
                        coordinator.copyHomebrewCLIUninstallCommand()
                    }
                case .availableViaForeign, .targetBlocked:
                    OFCompactButton(
                        title: OffsendStrings.settingsHooksCliPathInstall,
                        icon: "terminal",
                        variant: .outline
                    ) {
                        coordinator.installCLICommandInPath()
                    }
                    .disabled(true)
                }

                OFCompactButton(
                    title: OffsendStrings.settingsHooksCopyGlobalCommand,
                    icon: "doc.on.doc",
                    variant: .outline
                ) {
                    copyGlobalInstallCommand()
                }
                OFCompactButton(
                    title: OffsendStrings.settingsHooksRefreshStatuses,
                    icon: "arrow.clockwise",
                    variant: .outline
                ) {
                    coordinator.refreshHookedRepositoryStatuses()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func cliPathStatusBadge(_ state: CLIPathInstallationState) -> some View {
        let title: String
        let textColor: Color
        let bgColor: Color

        switch state {
        case .installed:
            title = OffsendStrings.settingsHooksCliPathStatusInstalled
            textColor = palette.greenText
            bgColor = palette.greenDim
        case .notInstalled:
            title = OffsendStrings.settingsHooksCliPathStatusMissing
            textColor = palette.textMuted
            bgColor = palette.bg3
        case .availableViaHomebrew:
            title = OffsendStrings.settingsHooksCliPathStatusHomebrew
            textColor = palette.blue
            bgColor = palette.blueDim
        case .availableViaForeign:
            title = OffsendStrings.settingsHooksCliPathStatusExternal
            textColor = palette.amberText
            bgColor = palette.amberDim
        case .targetBlocked:
            title = OffsendStrings.settingsHooksCliPathStatusBlocked
            textColor = palette.redText
            bgColor = palette.redDim
        case .brokenManagedLink:
            title = OffsendStrings.settingsHooksCliPathStatusBroken
            textColor = palette.amberText
            bgColor = palette.amberDim
        }

        return Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgColor)
            .cornerRadius(4)
    }

    private func cliPathStatusHint(_ status: CLIPathInstallationStatus) -> String {
        switch status.state {
        case .installed:
            return OffsendStrings.settingsHooksCliPathHintInstalled
        case .notInstalled:
            return OffsendStrings.settingsHooksCliPathHintMissing
        case .availableViaHomebrew:
            return OffsendStrings.settingsHooksCliPathHintHomebrew
        case .availableViaForeign:
            return OffsendStrings.settingsHooksCliPathHintExternal(status.commandPath ?? "offsend")
        case .targetBlocked:
            return OffsendStrings.settingsHooksCliPathHintBlocked(status.installPath)
        case .brokenManagedLink:
            return OffsendStrings.settingsHooksCliPathHintBroken
        }
    }

    private func addRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = OffsendStrings.settingsHooksAddProject

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = coordinator.addHookedRepository(url: url)
    }

    private func copyGlobalInstallCommand() {
        guard let command = coordinator.hookedRepositoryInstallCommand else {
            coordinator.lastStatusMessage = OffsendStrings.settingsHooksErrorCliNotFound
            return
        }
        coordinator.clipboardService.writeString(command)
        coordinator.lastStatusMessage = OffsendStrings.settingsHooksCopiedInstallCommand
    }
}
