import AppUIKit
import SwiftUI

struct DocumentSanitizeWorkingOverlay: View {
    let mode: DocumentSanitizeWorkingOverlayMode
    var documentName: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            VStack(spacing: OFSpacing.sm) {
                ProgressView()
                    .controlSize(.regular)

                Text(statusTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.ofText)

                if let documentName {
                    Text(documentName)
                        .font(.system(size: 11))
                        .foregroundColor(.ofTextMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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

    private var statusTitle: String {
        switch mode {
        case .analyzing:
            return OffsendStrings.documentSanitizeAnalyzing
        case .sanitizing:
            return OffsendStrings.documentSanitizeSanitizing
        case .refreshingPreview:
            return OffsendStrings.documentSanitizeRefreshingPreview
        }
    }
}
