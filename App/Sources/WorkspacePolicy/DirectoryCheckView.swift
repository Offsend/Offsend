import AppUIKit
import SwiftUI
import WorkspacePolicyCore

struct DirectoryCheckContentView: View {
    let directoryURL: URL
    let onReplaceSelection: (URL) -> Void

    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var viewModel: DirectoryCheckViewModel

    init(directoryURL: URL, onReplaceSelection: @escaping (URL) -> Void) {
        let standardized = directoryURL.standardizedFileURL
        self.directoryURL = standardized
        self.onReplaceSelection = onReplaceSelection
        _viewModel = StateObject(wrappedValue: DirectoryCheckViewModel(directoryURL: standardized))
    }

    var body: some View {
        directoryCheckRoot
    }

    @ViewBuilder
    private var directoryCheckRoot: some View {
        let showsFooter = viewModel.auditResult.map {
            viewModel.shouldShowPinnedFooter(for: $0, coordinator: coordinator)
        } ?? false
        let bodyHeight = viewModel.preferredWindowHeight()
        let windowSize = NSSize(
            width: PrepareWindowChrome.windowWidth(contentWidth: DirectoryCheckLayout.windowWidth),
            height: PrepareWindowChrome.windowHeight(bodyHeight: bodyHeight)
        )

        VStack(spacing: 0) {
            ScrollView {
                directoryBodyContent
            }
            .disabled(viewModel.isBusy)

            if showsFooter, let auditResult = viewModel.auditResult {
                DirectoryCheckFooter(viewModel: viewModel, result: auditResult)
            }
        }
        .frame(
            minWidth: DirectoryCheckLayout.windowWidth,
            maxWidth: .infinity,
            minHeight: bodyHeight,
            maxHeight: bodyHeight,
            alignment: .top
        )
        .background {
            DirectoryCheckWindowConfigurator(
                minimumSize: windowSize,
                preferredSize: windowSize,
                resetToken: viewModel.windowResetToken
            )
            .equatable()
        }
        .overlay {
            if viewModel.isBusy {
                DirectoryCheckWorkingOverlay(isApplyingFix: viewModel.isApplyingFix)
            }
        }
        .onAppear {
            viewModel.bind(coordinator: coordinator)
            viewModel.handleAppear()
        }
        .onDisappear(perform: viewModel.releaseSession)
        .onChange(of: coordinator.tariffFeatures) { _ in
            viewModel.audit(directoryURL: viewModel.selectedDirectory)
        }
        .onChange(of: viewModel.auditSettings(from: coordinator)) { _ in
            viewModel.audit(directoryURL: viewModel.selectedDirectory)
        }
    }

    @ViewBuilder
    private var directoryBodyContent: some View {
        VStack(alignment: .leading, spacing: OFSpacing.lg) {

            if let auditResult = viewModel.auditResult {
                DirectoryCheckFolderWatchCard(viewModel: viewModel, result: auditResult)

                if let fixMessage = viewModel.fixMessage {
                    OFSemanticBanner(
                        style: .info,
                        icon: "info.circle.fill",
                        title: OffsendStrings.directoryCheckFixResultTitle,
                        subtitle: fixMessage
                    )
                }

                if viewModel.isShowingCachedWatchStatus {
                    DirectoryCheckCachedWatchStatusSection(viewModel: viewModel, result: auditResult)
                } else {
                    if let auditDelta = viewModel.auditDelta {
                        DirectoryCheckAuditChangesSection(delta: auditDelta)
                    }

                    if viewModel.showsProtectedState(auditResult) {
                        protectedBanner(for: auditResult)
                        DirectoryCheckIssueSummaryBar(viewModel: viewModel, result: auditResult)
                        DirectoryCheckSatisfiedFindingsContent(result: auditResult)
                    } else {
                        DirectoryCheckIssueSummaryBar(viewModel: viewModel, result: auditResult)
                        DirectoryCheckFindingsContent(viewModel: viewModel, result: auditResult)
                    }
                }
            }
        }
        .padding(.horizontal, OFSpacing.md)
        .padding(.bottom, OFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func protectedBanner(for result: AIWorkspacePrivacyAuditResult) -> some View {
        let ruleCount = viewModel.totalPrivacyRules(for: result)
        let subtitle = viewModel.isWatchingSelectedDirectory(coordinator: coordinator)
            ? OffsendStrings.directoryCheckProtectedSubtitle(ruleCount)
            : OffsendStrings.directoryCheckProtectedSubtitleNoWatch(ruleCount)

        return OFSemanticBanner(
            style: .success,
            icon: "checkmark.shield",
            title: OffsendStrings.directoryCheckProtectedTitle,
            subtitle: subtitle
        )
    }
}
