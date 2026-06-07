import AppUIKit
import SwiftUI
import WorkspacePolicyCore

struct DirectoryCheckFindingsContent: View {
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult

    private var showsFixSelection: Bool {
        guard result.errors.isEmpty else { return false }
        if DirectoryCheckPresentation.hasNoIgnoreFiles(in: result),
           !DirectoryCheckPresentation.hasPatternErrors(in: result) {
            return true
        }
        return result.status != .pass
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
                            showsSeverityBadge: true,
                            tag: .fail
                        )
                    }
                }
            }

            if showsFixSelection {
                DirectoryCheckFixSelectionContent(viewModel: viewModel, result: result)
            } else if !result.errors.isEmpty {
                readOnlyFindingsForErrors
            }
        }
    }

    @ViewBuilder
    private var readOnlyFindingsForErrors: some View {
        if !result.missingSensitivePatterns.isEmpty {
            DirectoryCheckExposedPatternsCard(result: result)
        }

        let missingIgnoreRules = (result.missingRequiredRules + result.missingRecommendedRules)
            .filter(\.rule.scansForSensitivePatterns)
        if !missingIgnoreRules.isEmpty {
            DirectoryCheckFindingsCard(title: OffsendStrings.directoryCheckSectionMissingIgnoreFiles) {
                ForEach(Array(missingIgnoreRules.enumerated()), id: \.element.id) { index, finding in
                    if index > 0 { OFCardGroupDivider() }
                    DirectoryCheckReadOnlyFindingRow(
                        title: finding.rule.title,
                        subtitle: DirectoryCheckPresentation.ruleFindingSubtitle(for: finding),
                        showsSeverityBadge: false,
                        toolName: finding.rule.toolName
                    )
                }
            }
        }

        let otherProjectFiles = (result.missingRequiredRules + result.missingRecommendedRules)
            .filter { !$0.rule.scansForSensitivePatterns }
        if !otherProjectFiles.isEmpty {
            DirectoryCheckOtherProjectFilesCard(findings: otherProjectFiles)
        }
    }
}

private struct DirectoryCheckFixSelectionContent: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult

    var body: some View {
        let scenario = viewModel.fixScenario(for: result)

        VStack(alignment: .leading, spacing: OFSpacing.md) {
            if !result.missingSensitivePatterns.isEmpty {
                DirectoryCheckExposedPatternsCard(result: result)
            }

            switch scenario {
            case .existingPolicyFiles:
                let exposureGapItems = viewModel.exposureGapRuleFileItems(for: result, coordinator: coordinator)
                if !exposureGapItems.isEmpty {
                    DirectoryCheckRuleFileSelectionCard(
                        viewModel: viewModel,
                        result: result,
                        title: OffsendStrings.directoryCheckFixSelectionSectionUpdateFiles,
                        hint: OffsendStrings.directoryCheckFixSelectionSectionUpdateFilesHint,
                        items: exposureGapItems
                    )
                }

                let missingItems = viewModel.missingIgnoreFileItems(for: result, coordinator: coordinator)
                if !missingItems.isEmpty {
                    DirectoryCheckRuleFileSelectionCard(
                        viewModel: viewModel,
                        result: result,
                        title: OffsendStrings.directoryCheckFixSelectionSectionMissingFiles,
                        hint: OffsendStrings.directoryCheckFixSelectionSectionMissingFilesHint,
                        items: missingItems
                    )
                }

            case .noPolicyFiles:
                let missingItems = viewModel.missingIgnoreFileItems(for: result, coordinator: coordinator)
                if !missingItems.isEmpty {
                    DirectoryCheckRuleFileSelectionCard(
                        viewModel: viewModel,
                        result: result,
                        title: OffsendStrings.directoryCheckFixSelectionSectionChooseFile,
                        hint: OffsendStrings.directoryCheckFixSelectionSectionChooseFileHint,
                        items: missingItems
                    )
                }
            }

            if viewModel.showsPatternSelection(for: result, coordinator: coordinator) {
                DirectoryCheckImplicitPatternsNote()
            }

            let projectRuleItems = viewModel.projectRuleFileFixItems(for: result, coordinator: coordinator)
            if !projectRuleItems.isEmpty {
                DirectoryCheckRuleFileSelectionCard(
                    viewModel: viewModel,
                    result: result,
                    title: OffsendStrings.directoryCheckFixSelectionSectionProjectRules,
                    hint: OffsendStrings.directoryCheckFixSelectionSectionProjectRulesHint,
                    items: projectRuleItems
                )
            }

            let otherProjectFiles = viewModel.otherProjectFileFindings(for: result, coordinator: coordinator)
            if !otherProjectFiles.isEmpty {
                DirectoryCheckOtherProjectFilesCard(findings: otherProjectFiles)
            }

            if DirectoryCheckPresentation.hasSatisfiedFindings(in: result) {
                DirectoryCheckSatisfiedFindingsContent(result: result)
            }

            DirectoryCheckFixSelectionFooter(viewModel: viewModel, result: result)
        }
    }
}

struct DirectoryCheckSatisfiedFindingsContent: View {
    let result: AIWorkspacePrivacyAuditResult

    @ViewBuilder
    var body: some View {
        let satisfiedRules = DirectoryCheckPresentation.satisfiedRulesForDisplay(in: result)
        let satisfiedPatterns = DirectoryCheckPresentation.satisfiedPatternsForDisplay(in: result)
        if satisfiedRules.isEmpty, satisfiedPatterns.isEmpty {
            EmptyView()
        } else {
        let okCount = satisfiedRules.count + satisfiedPatterns.count

        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            HStack(spacing: OFSpacing.sm) {
                DirectoryCheckSectionHeader(title: OffsendStrings.directoryCheckSectionSatisfied)
                OFCountPill(count: okCount, style: .ok)
                Spacer(minLength: 0)
            }

            Text(OffsendStrings.directoryCheckSectionSatisfiedHint)
                .font(.system(size: 11))
                .foregroundColor(.ofTextMuted)
                .fixedSize(horizontal: false, vertical: true)

            OFCardGroup {
            ForEach(Array(satisfiedRules.enumerated()), id: \.element.id) { index, finding in
                if index > 0 { OFCardGroupDivider() }
                DirectoryCheckReadOnlyFindingRow(
                    title: finding.rule.title,
                    subtitle: DirectoryCheckPresentation.satisfiedRuleSubtitle(for: finding),
                    showsSeverityBadge: true,
                    tag: .pass,
                    toolName: finding.rule.toolName
                )
            }

            if !satisfiedRules.isEmpty, !satisfiedPatterns.isEmpty {
                OFCardGroupDivider()
            }

            ForEach(Array(satisfiedPatterns.enumerated()), id: \.element.id) { index, finding in
                if index > 0 { OFCardGroupDivider() }
                DirectoryCheckReadOnlyFindingRow(
                    title: finding.pattern.title,
                    subtitle: DirectoryCheckPresentation.satisfiedPatternSubtitle(for: finding),
                    showsSeverityBadge: true,
                    tag: .pass
                )
            }
            }
        }
        }
    }
}

private struct DirectoryCheckExposedPatternsCard: View {
    let result: AIWorkspacePrivacyAuditResult

    var body: some View {
        DirectoryCheckFindingsCard(
            title: OffsendStrings.directoryCheckSectionSensitivePatterns,
            hint: OffsendStrings.directoryCheckSectionSensitivePatternsHint
        ) {
            ForEach(Array(result.missingSensitivePatterns.enumerated()), id: \.element.id) { index, finding in
                if index > 0 { OFCardGroupDivider() }
                DirectoryCheckReadOnlyFindingRow(
                    title: finding.pattern.title,
                    subtitle: DirectoryCheckPresentation.sensitivePatternSubtitle(for: finding),
                    showsSeverityBadge: true,
                    tag: DirectoryCheckPresentation.severityTag(finding.pattern.severity)
                )
            }
        }
    }
}

private struct DirectoryCheckOtherProjectFilesCard: View {
    let findings: [AIWorkspacePrivacyRuleFinding]

    var body: some View {
        DirectoryCheckFindingsCard(
            title: OffsendStrings.directoryCheckSectionOtherProjectFiles,
            hint: OffsendStrings.directoryCheckSectionOtherProjectFilesHint
        ) {
            ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                if index > 0 { OFCardGroupDivider() }
                DirectoryCheckReadOnlyFindingRow(
                    title: finding.rule.title,
                    subtitle: DirectoryCheckPresentation.ruleFindingSubtitle(for: finding),
                    showsSeverityBadge: false,
                    toolName: finding.rule.toolName,
                    icon: "doc.text",
                    iconTint: .ofTextMuted
                )
            }
        }
    }
}

private struct DirectoryCheckImplicitPatternsNote: View {
    var body: some View {
        Text(OffsendStrings.directoryCheckFixSelectionImplicitPatternsNote)
            .font(.system(size: 11))
            .foregroundColor(.ofTextMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DirectoryCheckRuleFileSelectionCard: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult
    let title: String
    var hint: String?
    let items: [AIWorkspacePrivacyFixItem]

    var body: some View {
        let showsSelectAll = items.count > 1

        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            HStack {
                DirectoryCheckSectionHeader(title: title)

                if showsSelectAll {
                    Spacer()

                    Button {
                        viewModel.toggleSelectAllRuleFiles(
                            items: items,
                            for: result,
                            coordinator: coordinator
                        )
                    } label: {
                        Text(
                            viewModel.allRuleFilesSelected(items: items)
                                ? OffsendStrings.directoryCheckFixSelectionDeselectAll
                                : OffsendStrings.directoryCheckFixSelectionSelectAll
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ofBlue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OFCardGroup {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { OFCardGroupDivider() }
                    DirectoryCheckFixRow(viewModel: viewModel, result: result, item: item)
                }
            }
        }
    }
}

private struct DirectoryCheckFixSelectionFooter: View {
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult

    var body: some View {
        if !viewModel.hasSelectedFixItems {
            Text(OffsendStrings.directoryCheckFixSelectionNoneSelected)
                .font(.system(size: 11))
                .foregroundColor(.ofAmberText)
        }
    }
}

private struct DirectoryCheckFixRow: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult
    let item: AIWorkspacePrivacyFixItem

    var body: some View {
        let content = viewModel.fixRowContent(for: result, item: item, itemID: item.id)
        let highlightsAsFixTarget = viewModel.isUpdatingExistingIgnoreFile(item, result: result)

        OFSelectableFixRow(
            title: item.title,
            toolName: item.toolName,
            description: content.description,
            isSelected: viewModel.selectedFixItemIDs.contains(item.id),
            isEnabled: true,
            highlightsAsFixTarget: highlightsAsFixTarget
        ) {
            viewModel.toggleFixItemSelection(item.id, result: result, coordinator: coordinator)
        }
    }
}

private struct DirectoryCheckFindingsCard<Content: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            DirectoryCheckSectionHeader(title: title)

            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OFCardGroup {
                content()
            }
        }
    }
}

private struct DirectoryCheckReadOnlyFindingRow: View {
    let title: String
    let subtitle: String
    var showsSeverityBadge: Bool = false
    var tag: DirectoryCheckFindingTag = .info
    var toolName: String?
    var icon: String?
    var iconTint: Color = .ofTextMuted

    var body: some View {
        HStack(alignment: .top, spacing: OFSpacing.md) {
            if showsSeverityBadge {
                OFStatusBadge(style: tag.badgeStyle, compact: true)
                    .padding(.top, 2)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconTint)
                    .frame(width: 28, alignment: .center)
                    .padding(.top, 2)
            }

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
