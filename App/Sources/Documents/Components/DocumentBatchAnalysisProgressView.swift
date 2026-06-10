import AppUIKit
import SwiftUI

struct DocumentBatchAnalysisProgressView: View {
    let progress: DocumentBatchAnalysisProgress

    var body: some View {
        Text(OffsendStrings.documentSanitizeBatchAnalyzing(progress.finishedCount, progress.totalCount))
            .font(.system(size: 11))
            .foregroundColor(.ofTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: DocumentSanitizeLayout.batchProgressHeight)
    }
}
