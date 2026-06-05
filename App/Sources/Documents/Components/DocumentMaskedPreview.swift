import AppUIKit
import SwiftUI

struct DocumentMaskedPreview: View, Equatable {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            DocumentSanitizeSectionHeader(title: OffsendStrings.documentSanitizeMaskedPreview)

            ScrollView(.vertical) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ofTextSub)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.ofBg2)
            .cornerRadius(OFRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.md)
                    .stroke(Color.ofBorder, lineWidth: 1)
            )
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
