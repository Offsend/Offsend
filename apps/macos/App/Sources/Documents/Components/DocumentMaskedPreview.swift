import AppUIKit
import DocumentCore
import SwiftUI

struct DocumentMaskedPreview: View {
    @ObservedObject var viewModel: DocumentSanitizeViewModel
    let result: DocumentAnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            DocumentSanitizeSectionHeader(title: OffsendStrings.documentSanitizeMaskedPreview)

            ZStack(alignment: .bottomTrailing) {
                ScrollView(.vertical) {
                    Text(viewModel.previewText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.ofTextSub)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .padding(.bottom, DocumentSanitizeLayout.maskedPreviewCopyButtonReserve)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.ofBg2)
                .cornerRadius(OFRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: OFRadius.md)
                        .stroke(Color.ofBorder, lineWidth: 1)
                )

                DocumentPreviewCopyButton(viewModel: viewModel, result: result)
                    .padding(OFSpacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
