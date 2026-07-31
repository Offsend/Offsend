import AppKit
import AppUIKit
import SwiftUI

struct DocumentSanitizeContentView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var batchViewModel: DocumentBatchSanitizeViewModel

    init(fileURLs: [URL]) {
        let standardized = fileURLs.map(\.standardizedFileURL)
        _batchViewModel = StateObject(wrappedValue: DocumentBatchSanitizeViewModel(fileURLs: standardized))
    }

    private var viewModel: DocumentSanitizeViewModel {
        batchViewModel.activeViewModel
    }

    var body: some View {
        documentSanitizeRoot
    }

    @ViewBuilder
    private var documentSanitizeRoot: some View {
        let bodyHeight = batchViewModel.preferredWindowHeight()
        let minimumSize = NSSize(
            width: PrepareWindowChrome.windowWidth(contentWidth: DocumentSanitizeLayout.windowWidth),
            height: PrepareWindowChrome.windowHeight(bodyHeight: bodyHeight)
        )
        let showsFindingsFooter = batchViewModel.showsFindingsFooter(for: viewModel)
        let showsFileTooLargeFooter = batchViewModel.showsFileTooLargeFooter(for: viewModel)

        VStack(spacing: 0) {
            documentBodyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .disabled(batchViewModel.isActiveDocumentBusy)

            if showsFileTooLargeFooter {
                DocumentSanitizeFileTooLargeFooter(isBusy: viewModel.isBusy) {
                    Task { await coordinator.openProCheckout(prefillEmail: nil, source: "document_sanitize_file_size") }
                }
            } else if showsFindingsFooter, let analysisResult = viewModel.analysisResult {
                DocumentSanitizeFooter(
                    batchViewModel: batchViewModel,
                    viewModel: viewModel,
                    result: analysisResult
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: DocumentSanitizeLayout.windowWidth, minHeight: bodyHeight)
        .background {
            DocumentSanitizeWindowConfigurator(
                minimumSize: minimumSize,
                preferredSize: minimumSize,
                resetToken: batchViewModel.layoutResetToken
            )
            .equatable()
        }
        .overlay {
            if let overlayMode = batchViewModel.activeOverlayMode {
                DocumentSanitizeWorkingOverlay(
                    mode: overlayMode,
                    documentName: batchViewModel.showsDocumentTabs ? batchViewModel.activeDocumentName : nil
                )
            }
        }
        .onAppear {
            batchViewModel.bind(coordinator: coordinator)
            batchViewModel.handleAppear()
        }
        .onDisappear(perform: batchViewModel.releaseSession)
    }

    @ViewBuilder
    private var documentBodyContent: some View {
        VStack(alignment: .leading, spacing: OFSpacing.lg) {
            if batchViewModel.showsDocumentTabs {
                DocumentTabBar(batchViewModel: batchViewModel)

                if let progress = batchViewModel.batchAnalysisProgress {
                    DocumentBatchAnalysisProgressView(progress: progress)
                }
            }

            if let analysisResult = viewModel.analysisResult {
                DocumentFindingsPreviewLayout(viewModel: viewModel, result: analysisResult)
            } else if let errorMessage = viewModel.errorMessage,
                      !viewModel.isBusy,
                      !viewModel.showsFileTooLargeBuyPro {
                documentErrorState(message: errorMessage)
            } else if !viewModel.isBusy {
                OFButton(
                    title: "",
                    variant: .outline,
                    icon: "arrow.clockwise",
                    small: true
                ) {
                    viewModel.analyze(fileURL: viewModel.selectedFile)
                }
            }
        }
        .padding(.horizontal, OFSpacing.md)
        .padding(.bottom, OFSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(viewModel.selectedFile)
    }

    @ViewBuilder
    private func documentErrorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Text(OffsendStrings.documentSanitizeErrorTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.ofText)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.ofTextMuted)
                .fixedSize(horizontal: false, vertical: true)

            OFButton(
                title: "",
                variant: .outline,
                icon: "arrow.clockwise",
                small: true
            ) {
                viewModel.analyze(fileURL: viewModel.selectedFile)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
