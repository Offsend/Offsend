import AppUIKit
import DocumentCore
import SwiftUI

struct DocumentSanitizeFooter: View {
    @ObservedObject var batchViewModel: DocumentBatchSanitizeViewModel
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

                if batchViewModel.showsDocumentTabs {
                    OFButton(
                        title: OffsendStrings.documentSanitizeSaveAllPrepared,
                        variant: .outline,
                        icon: "square.and.arrow.down.on.square",
                        small: true,
                        disabled: !batchViewModel.canSaveAllPrepared
                    ) {
                        batchViewModel.saveAllPrepared()
                    }
                }

                OFButton(
                    title: OffsendStrings.documentSanitizeSaveAs,
                    variant: .primary,
                    icon: "square.and.arrow.down",
                    small: true,
                    disabled: !viewModel.canSaveDocument(for: result) || batchViewModel.isSavingAll
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
