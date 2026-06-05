import AppKit
import AppUIKit
import SwiftUI

struct DocumentSanitizeContentView: View {
    let fileURL: URL
    let onReplaceSelection: (URL) -> Void

    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var viewModel: DocumentSanitizeViewModel

    init(fileURL: URL, onReplaceSelection: @escaping (URL) -> Void) {
        let standardized = fileURL.standardizedFileURL
        self.fileURL = standardized
        self.onReplaceSelection = onReplaceSelection
        _viewModel = StateObject(wrappedValue: DocumentSanitizeViewModel(fileURL: standardized))
    }

    var body: some View {
        documentSanitizeRoot
    }

    @ViewBuilder
    private var documentSanitizeRoot: some View {
        let bodyHeight = viewModel.preferredWindowHeight()
        let minimumSize = NSSize(
            width: PrepareWindowChrome.windowWidth(contentWidth: DocumentSanitizeLayout.windowWidth),
            height: PrepareWindowChrome.windowHeight(bodyHeight: bodyHeight)
        )
        let showsFindingsFooter = viewModel.analysisResult.map { viewModel.shouldShowPinnedFooter(for: $0) } ?? false
        let showsFileTooLargeFooter = viewModel.showsFileTooLargeBuyPro

        VStack(spacing: 0) {
            documentBodyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .disabled(viewModel.isBusy)

            if showsFileTooLargeFooter {
                DocumentSanitizeFileTooLargeFooter(isBusy: viewModel.isBusy) {
                    Task { await coordinator.openProCheckout(prefillEmail: nil, source: "document_sanitize_file_size") }
                }
            } else if showsFindingsFooter, let analysisResult = viewModel.analysisResult {
                DocumentSanitizeFooter(viewModel: viewModel, result: analysisResult)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: DocumentSanitizeLayout.windowWidth, minHeight: bodyHeight)
        .background {
            DocumentSanitizeWindowConfigurator(
                minimumSize: minimumSize,
                preferredSize: minimumSize,
                resetToken: viewModel.windowResetToken
            )
            .equatable()
        }
        .overlay {
            if viewModel.isBusy {
                DocumentSanitizeWorkingOverlay(isSanitizing: viewModel.isSanitizing)
            }
        }
        .onAppear {
            viewModel.bind(coordinator: coordinator)
            viewModel.handleAppear()
        }
        .onDisappear(perform: viewModel.releaseSession)
    }

    @ViewBuilder
    private var documentBodyContent: some View {
        VStack(alignment: .leading, spacing: OFSpacing.lg) {
            if let analysisResult = viewModel.analysisResult {
                if viewModel.showsFindingsLayout(for: analysisResult) {
                    DocumentFindingsPreviewLayout(viewModel: viewModel, result: analysisResult)
                } else {
                    DocumentSafeResultView()
                }
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
    }
}
