import AppUIKit
import SwiftUI
import WorkspacePolicyCore

struct DirectoryCheckFolderWatchCard: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult

    private var watchToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isWatchingSelectedDirectory(coordinator: coordinator) },
            set: { viewModel.toggleWatchForSelectedDirectory(enabled: $0, coordinator: coordinator) }
        )
    }

    var body: some View {
        OFCardGroup {
            HStack(alignment: .center, spacing: OFSpacing.md) {
                OFIconTile(systemName: "folder.fill", tint: .ofTextMuted, size: 32, iconSize: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.directoryURL.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ofText)
                        .lineLimit(1)

                    Text(DirectoryCheckPresentation.displayPath(for: result.directoryURL))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.ofTextSub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                OFStatusCapsule(
                    style: DirectoryCheckPresentation.statusBadgeStyle(for: result.status),
                    title: DirectoryCheckPresentation.statusTitle(for: result.status)
                )
            }
            .padding(.horizontal, OFSpacing.md)
            .padding(.vertical, 12)

            OFCardGroupDivider()

            OFCardRow(
                icon: "eye.fill",
                iconTint: .ofBlue,
                title: OffsendStrings.directoryCheckWatchInBackground,
                subtitle: viewModel.watchSubtitle(coordinator: coordinator),
                subtitleTint: viewModel.watchSubtitleTint(coordinator: coordinator),
                highlighted: viewModel.isWatchingSelectedDirectory(coordinator: coordinator)
            ) {
                HStack(spacing: OFSpacing.sm) {
                    if viewModel.showsWatchFreePlanUpgrade(coordinator: coordinator) {
                        OFCompactButton(
                            title: OffsendStrings.directoryCheckProUpsellCta,
                            icon: "crown.fill",
                            variant: .outline
                        ) {
                            Task { await coordinator.upgradeFromWatchLimit(source: "directory_check") }
                        }
                    }

                    OFToggle(isOn: watchToggleBinding)
                        .disabled(!viewModel.isWatchToggleEnabled(coordinator: coordinator))
                }
            }
        }
    }
}
