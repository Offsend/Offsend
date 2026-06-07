import AppUIKit
import SwiftUI
import WorkspacePolicyCore

struct DirectoryCheckCachedWatchStatusSection: View {
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            HStack(alignment: .top, spacing: OFSpacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13))
                    .foregroundColor(.ofBlue)
                    .padding(.top, 1)

                Text(OffsendStrings.directoryCheckCachedWatchStatusHint)
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(OFSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ofBlueDim)
            .cornerRadius(OFRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.md)
                    .stroke(Color.ofBlue.opacity(0.25), lineWidth: 1)
            )

            HStack(spacing: OFSpacing.sm) {
                Text(OffsendStrings.directoryCheckCachedWatchStatusSummary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ofText)

                let displayStatus = DirectoryCheckPresentation.displayStatus(for: result)
                OFStatusCapsule(
                    style: DirectoryCheckPresentation.displayStatusBadgeStyle(for: displayStatus),
                    title: DirectoryCheckPresentation.displayStatusTitle(for: result)
                )

                Spacer(minLength: 0)
            }
        }
    }
}
