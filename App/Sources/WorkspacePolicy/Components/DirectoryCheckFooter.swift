import AppUIKit
import SwiftUI
import WorkspacePolicyCore

struct DirectoryCheckFooter: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var viewModel: DirectoryCheckViewModel
    let result: AIWorkspacePrivacyAuditResult

    var body: some View {
        if viewModel.selectionRequiresPro(for: result, coordinator: coordinator) {
            OFPinnedActionFooter(
                statusText: OffsendStrings.directoryCheckProSelectionNote,
                buttonTitle: OffsendStrings.directoryCheckBuyPro,
                buttonIcon: "crown.fill",
                buttonDisabled: viewModel.isBusy
            ) {
                Task { await coordinator.openProCheckout(prefillEmail: nil) }
            }
        } else {
            let selectedCount = viewModel.selectedFixItemIDs.count
            OFPinnedActionFooter(
                statusText: OffsendStrings.directoryCheckFixesSelected(selectedCount),
                buttonTitle: selectedCount == 1
                    ? OffsendStrings.directoryCheckApplyFix
                    : OffsendStrings.directoryCheckApplyFixes(selectedCount),
                buttonDisabled: viewModel.isBusy || !viewModel.canApplyFixSelection(for: result, coordinator: coordinator)
            ) {
                viewModel.fix(result, coordinator: coordinator)
            }
        }
    }
}
