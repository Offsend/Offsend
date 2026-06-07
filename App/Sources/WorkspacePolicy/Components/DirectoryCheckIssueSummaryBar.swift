import AppUIKit
import SwiftUI
import WorkspacePolicyCore

struct DirectoryCheckIssueSummaryBar: View {
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult

    var body: some View {
        let counts = DirectoryCheckPresentation.issueCounts(for: result)

        HStack(spacing: OFSpacing.sm) {
            Text(DirectoryCheckPresentation.issueSummaryTitle(for: counts))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.ofText)

            if counts.fail > 0 {
                OFCountPill(count: counts.fail, style: .fail)
            }
            if counts.info > 0 {
                OFCountPill(count: counts.info, style: .info)
            }

            Spacer(minLength: 0)

            OFButton(
                title: OffsendStrings.directoryCheckRefreshAudit,
                variant: .outline,
                icon: "arrow.clockwise",
                small: true
            ) {
                viewModel.audit(directoryURL: result.directoryURL)
            }
            .disabled(viewModel.isBusy)
        }
    }
}
