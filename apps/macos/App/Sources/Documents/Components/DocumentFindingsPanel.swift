import AppUIKit
import DocumentCore
import SwiftUI

struct DocumentFindingsPanel: View {
    @ObservedObject var viewModel: DocumentSanitizeViewModel
    let result: DocumentAnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            HStack {
                DocumentSanitizeSectionHeader(title: OffsendStrings.documentSanitizeDetectedEntities)

                Spacer()

                if !result.detection.entities.isEmpty {
                    Button {
                        viewModel.toggleSelectAll(for: result)
                    } label: {
                        Text(
                            viewModel.allEntitiesSelected(for: result)
                                ? OffsendStrings.documentSanitizeDeselectAll
                                : OffsendStrings.documentSanitizeSelectAll
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ofBlue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if result.detection.entities.isEmpty {
                DocumentNoDetectedEntitiesCard(result: result)
            } else {
                OFCardGroup {
                    ForEach(Array(viewModel.entityGroups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { OFCardGroupDivider() }
                        DocumentEntityGroupRow(
                            group: group,
                            isSelected: viewModel.isEntityGroupSelected(group),
                            onToggle: { viewModel.toggleEntityGroup(group, for: result) }
                        )
                    }
                }
            }

            VStack {
                if !result.detection.entities.isEmpty, viewModel.selectedEntityIDs.isEmpty {
                    Text(OffsendStrings.documentSanitizeNoEntitiesSelected)
                        .font(.system(size: 11))
                        .foregroundColor(.ofAmberText)
                }
            }
            .frame(height: 12)

            HStack(spacing: OFSpacing.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(OffsendStrings.documentSanitizeRiskScore)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ofText)

                    if let assessment = viewModel.currentAssessment {
                        OFRiskMeterBar(
                            risk: DocumentSanitizePresentation.uiRisk(for: assessment),
                            score: min(assessment.score, 100),
                            totalBars: 20
                        )
                        .animation(.easeInOut(duration: 0.2), value: assessment.score)
                    }
                }

                Spacer(minLength: 0)

                OFButton(
                    title: "",
                    variant: .outline,
                    icon: "arrow.clockwise",
                    small: true
                ) {
                    viewModel.reanalyze()
                }
                .disabled(viewModel.isBusy)
            }
        }
    }
}

private struct DocumentEntityGroupRow: View {
    let group: DocumentSanitizeEntityGroup
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        OFSelectableFixRow(
            badgeStyle: DocumentSanitizePresentation.severityBadgeStyle(for: group.type),
            title: AppLocalization.sensitiveEntityTypeName(group.type, plural: group.entities.count != 1),
            description: OffsendStrings.documentSanitizeEntityGroupSummary(group.entities.count),
            isSelected: isSelected,
            action: onToggle
        )
    }
}

private struct DocumentNoDetectedEntitiesCard: View {
    let result: DocumentAnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Text(OffsendStrings.documentSanitizeSafeTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.ofText)

            Text(
                result.extracted.format == .pdf
                    ? OffsendStrings.documentSanitizeEditRedactionsHint
                    : OffsendStrings.documentSanitizeSafeSubtitle
            )
            .font(.system(size: 11))
            .foregroundColor(.ofTextSub)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OFSpacing.md)
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBorder, lineWidth: 1)
        )
    }
}
