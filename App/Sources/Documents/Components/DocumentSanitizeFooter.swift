import AppUIKit
import DocumentCore
import SwiftUI

struct DocumentSanitizeFooter: View {
    @ObservedObject var viewModel: DocumentSanitizeViewModel
    let result: DocumentAnalysisResult

    var body: some View {
        VStack(spacing: 0) {
            OFDivider()

            HStack(spacing: OFSpacing.md) {
                Text(OffsendStrings.documentSanitizeEntitiesSelected(viewModel.selectedGroupCount(for: result)))
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextMuted)
                    .lineLimit(1)

                Spacer(minLength: 0)

                OFButton(
                    title: OffsendStrings.documentSanitizeCopySafeText,
                    variant: .outline,
                    icon: "doc.on.doc",
                    small: true,
                    disabled: viewModel.isBusy || viewModel.selectedEntityIDs.isEmpty
                ) {
                    viewModel.copySafeText(for: result)
                }

                OFButton(
                    title: OffsendStrings.documentSanitizeSaveAs,
                    variant: .primary,
                    icon: "square.and.arrow.down",
                    small: true,
                    disabled: viewModel.isBusy || (viewModel.isPdfDocument ? !viewModel.canExportPdfRedaction : viewModel.selectedEntityIDs.isEmpty)
                ) {
                    viewModel.saveDocument(for: result)
                }
            }
            .padding(.horizontal, OFSpacing.md)
            .padding(.vertical, OFSpacing.md)
            .background(Color.ofBg0)
        }
    }
}
