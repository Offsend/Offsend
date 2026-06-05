import AppUIKit
import SwiftUI
import WorkspacePolicyCore

struct DirectoryCheckFindingsContent: View {
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult

    private var showsFixSelection: Bool {
        result.errors.isEmpty && result.status != .pass
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.md) {
            if !result.errors.isEmpty {
                DirectoryCheckFindingsCard(title: OffsendStrings.directoryCheckSectionErrors) {
                    ForEach(Array(result.errors.enumerated()), id: \.element.id) { index, error in
                        if index > 0 { OFCardGroupDivider() }
                        DirectoryCheckReadOnlyFindingRow(
                            title: error.message,
                            subtitle: error.id,
                            tag: .fail
                        )
                    }
                }
            }

            if showsFixSelection {
                DirectoryCheckSuggestedFixesCard(viewModel: viewModel, result: result)
            } else {
                if !result.missingRequiredRules.isEmpty {
                    DirectoryCheckFindingsCard(title: OffsendStrings.directoryCheckSectionRequired) {
                        ForEach(Array(result.missingRequiredRules.enumerated()), id: \.element.id) { index, finding in
                            if index > 0 { OFCardGroupDivider() }
                            DirectoryCheckReadOnlyFindingRow(
                                title: finding.rule.title,
                                subtitle: DirectoryCheckPresentation.ruleFindingSubtitle(for: finding),
                                tag: .fail,
                                toolName: finding.rule.toolName
                            )
                        }
                    }
                }

                if !result.missingSensitivePatterns.isEmpty {
                    DirectoryCheckFindingsCard(title: OffsendStrings.directoryCheckSectionSensitivePatterns) {
                        ForEach(Array(result.missingSensitivePatterns.enumerated()), id: \.element.id) { index, finding in
                            if index > 0 { OFCardGroupDivider() }
                            DirectoryCheckReadOnlyFindingRow(
                                title: finding.pattern.title,
                                subtitle: DirectoryCheckPresentation.sensitivePatternSubtitle(for: finding),
                                tag: DirectoryCheckPresentation.severityTag(finding.pattern.severity)
                            )
                        }
                    }
                }

                if !result.missingRecommendedRules.isEmpty {
                    DirectoryCheckFindingsCard(title: OffsendStrings.directoryCheckSectionRecommended) {
                        ForEach(Array(result.missingRecommendedRules.enumerated()), id: \.element.id) { index, finding in
                            if index > 0 { OFCardGroupDivider() }
                            DirectoryCheckReadOnlyFindingRow(
                                title: finding.rule.title,
                                subtitle: DirectoryCheckPresentation.ruleFindingSubtitle(for: finding),
                                tag: .warn,
                                toolName: finding.rule.toolName
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct DirectoryCheckSuggestedFixesCard: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult

    var body: some View {
        let items = viewModel.fixItems(for: result, coordinator: coordinator)

        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            HStack {
                DirectoryCheckSectionHeader(title: OffsendStrings.directoryCheckSuggestedFixes)

                Spacer()

                Button {
                    viewModel.toggleSelectAllFixItems(for: result, coordinator: coordinator)
                } label: {
                    Text(
                        viewModel.allFixItemsSelected(for: result, coordinator: coordinator)
                            ? OffsendStrings.directoryCheckFixSelectionDeselectAll
                            : OffsendStrings.directoryCheckFixSelectionSelectAll
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ofBlue)
                }
                .buttonStyle(.plain)
            }

            OFCardGroup {
                ForEach(Array(items.map(\.id).enumerated()), id: \.element) { index, itemID in
                    if index > 0 { OFCardGroupDivider() }
                    DirectoryCheckFixRow(viewModel: viewModel, result: result, itemID: itemID)
                }
            }

            if !viewModel.hasSelectedFixItems {
                Text(OffsendStrings.directoryCheckFixSelectionNoneSelected)
                    .font(.system(size: 11))
                    .foregroundColor(.ofAmberText)
            } else if viewModel.hasSelectedPatternsWithoutTargets(for: result, coordinator: coordinator) {
                Text(OffsendStrings.directoryCheckFixSelectionNoPatternTargets)
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextMuted)
            }
        }
    }
}

private struct DirectoryCheckFixRow: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult
    let itemID: String

    var body: some View {
        let policyFilesEnabled = viewModel.hasSelectedPolicyFiles(for: result, coordinator: coordinator)
        if let item = viewModel.fixItems(for: result, coordinator: coordinator).first(where: { $0.id == itemID }) {
            let content = viewModel.fixRowContent(for: result, item: item, itemID: itemID)

            OFSelectableFixRow(
                badgeStyle: DirectoryCheckPresentation.severityTag(item.severity).badgeStyle,
                title: item.title,
                toolName: item.toolName,
                description: content.description,
                isSelected: viewModel.selectedFixItemIDs.contains(itemID),
                isEnabled: content.isPattern ? policyFilesEnabled : true,
                isProLocked: viewModel.isProOnlyFixItem(item, coordinator: coordinator)
            ) {
                viewModel.toggleFixItemSelection(itemID, result: result, coordinator: coordinator)
            }
        }
    }
}

private struct DirectoryCheckFindingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            DirectoryCheckSectionHeader(title: title)

            OFCardGroup {
                content()
            }
        }
    }
}

private struct DirectoryCheckReadOnlyFindingRow: View {
    let title: String
    let subtitle: String
    let tag: DirectoryCheckFindingTag
    var toolName: String?

    var body: some View {
        HStack(alignment: .top, spacing: OFSpacing.md) {
            OFStatusBadge(style: tag.badgeStyle, compact: true)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.ofText)

                    if let toolName {
                        Text(toolName)
                            .font(.system(size: 12))
                            .foregroundColor(.ofTextMuted)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, OFSpacing.md)
        .padding(.vertical, 12)
    }
}
