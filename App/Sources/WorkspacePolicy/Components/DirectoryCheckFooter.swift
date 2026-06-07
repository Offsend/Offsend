import AppUIKit
import SwiftUI
import WorkspacePolicyCore

struct DirectoryCheckFooter: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult

    var body: some View {
        let summary = viewModel.fixApplySummary(for: result, coordinator: coordinator)
        OFPinnedActionFooter(
            statusText: DirectoryCheckPresentation.fixFooterStatusText(for: summary),
            buttonTitle: DirectoryCheckPresentation.applyButtonTitle(for: summary),
            buttonDisabled: viewModel.isBusy || !viewModel.canApplyFixSelection(for: result, coordinator: coordinator)
        ) {
            viewModel.fix(result, coordinator: coordinator)
        }
    }
}
