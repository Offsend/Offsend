import AppUIKit
import DocumentCore
import SwiftUI

struct DocumentPDFPreviewPanel: View {
    @ObservedObject var viewModel: DocumentSanitizeViewModel
    let result: DocumentAnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {

            HStack {
                DocumentSanitizeSectionHeader(title: OffsendStrings.documentSanitizeRedactedPreview)

                Spacer()

                if let plan = viewModel.redactionPlan, !plan.unresolvedValues.isEmpty {
                    Text(OffsendStrings.documentSanitizeUnresolvedRedactions(plan.unresolvedValues.count))
                        .font(.system(size: 11))
                        .foregroundColor(.ofAmberText)
                        .padding(.horizontal, 2)
                }
            }

            ZStack {
                PDFRedactionEditorView(
                    document: viewModel.pdfEditorDocument,
                    regions: viewModel.pdfOverlayBoxes,
                    canUndo: viewModel.canUndoManualRegions,
                    canRedo: viewModel.canRedoManualRegions,
                    isToolbarDisabled: viewModel.isBusy,
                    undoAccessibilityLabel: OffsendStrings.documentSanitizeUndo,
                    redoAccessibilityLabel: OffsendStrings.documentSanitizeRedo,
                    copyAccessibilityLabel: OffsendStrings.documentSanitizeCopySafeText,
                    canCopy: !viewModel.selectedEntityIDs.isEmpty,
                    onUndo: { viewModel.undoManualRegions(for: result) },
                    onRedo: { viewModel.redoManualRegions(for: result) },
                    onCopy: { viewModel.copySafeText(for: result) },
                    onManualRegionAdded: { pageIndex, bounds in
                        viewModel.addManualRegion(pageIndex: pageIndex, bounds: bounds, for: result)
                    }
                )
                .id(viewModel.selectedFile)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: DocumentSanitizeLayout.pdfPreviewMinHeight)

                if viewModel.isRefreshingPdfPreview {
                    DocumentPDFPreviewRefreshingOverlay()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct DocumentPDFPreviewRefreshingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
            VStack(spacing: OFSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text(OffsendStrings.documentSanitizeRefreshingPreview)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.ofTextSub)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: OFRadius.md))
    }
}
