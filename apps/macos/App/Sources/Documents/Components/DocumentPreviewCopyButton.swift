import AppUIKit
import DocumentCore
import SwiftUI

struct DocumentPreviewCopyButton: View {
    @ObservedObject var viewModel: DocumentSanitizeViewModel
    let result: DocumentAnalysisResult

    var body: some View {
        OFButton(
            title: "",
            variant: .outline,
            icon: "doc.on.doc",
            small: true,
            disabled: viewModel.isBusy || viewModel.selectedEntityIDs.isEmpty
        ) {
            viewModel.copySafeText(for: result)
        }
        .help(OffsendStrings.documentSanitizeCopySafeText)
    }
}
