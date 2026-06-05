import AppUIKit
import SwiftUI

struct DocumentSanitizeWorkingOverlay: View {
    let isSanitizing: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            VStack(spacing: OFSpacing.md) {
                ProgressView()
                    .controlSize(.regular)
                Text(isSanitizing ? OffsendStrings.documentSanitizeSanitizing : OffsendStrings.documentSanitizeAnalyzing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.ofText)
            }
            .padding(OFSpacing.xl)
            .background(Color.ofBg2)
            .cornerRadius(OFRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.lg)
                    .stroke(Color.ofBorder, lineWidth: 1)
            )
        }
    }
}
