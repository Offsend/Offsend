import DocumentCore
import SwiftUI

struct DocumentFindingsPreviewLayout: View {
    @ObservedObject var viewModel: DocumentSanitizeViewModel
    let result: DocumentAnalysisResult

    var body: some View {
        HStack(alignment: .top, spacing: DocumentSanitizeLayout.interColumnSpacing) {
            ScrollView {
                DocumentFindingsPanel(viewModel: viewModel, result: result)
            }
            .frame(width: DocumentSanitizeLayout.findingsContentWidth, alignment: .leading)

            Group {
                if result.extracted.format == .pdf {
                    DocumentPDFPreviewPanel(viewModel: viewModel, result: result)
                } else {
                    DocumentMaskedPreview(text: viewModel.previewText)
                        .equatable()
                }
            }
            .frame(
                minWidth: DocumentSanitizeLayout.documentPreviewMinWidth,
                maxWidth: .infinity,
                minHeight: DocumentSanitizeLayout.pdfPreviewMinHeight,
                maxHeight: .infinity,
                alignment: .top
            )
            .layoutPriority(1)
        }
        .frame(minHeight: DocumentSanitizeLayout.findingsResultHeight, maxHeight: .infinity, alignment: .top)
    }
}
