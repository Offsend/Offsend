import AppUIKit
import SwiftUI

struct DocumentTabBar: View {
    @ObservedObject var batchViewModel: DocumentBatchSanitizeViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OFSpacing.sm) {
                ForEach(Array(batchViewModel.fileURLs.enumerated()), id: \.offset) { index, fileURL in
                    DocumentTabButton(
                        title: fileURL.lastPathComponent,
                        status: batchViewModel.tabStatus(for: index),
                        isSelected: batchViewModel.activeDocumentIndex == index
                    ) {
                        batchViewModel.selectDocument(at: index)
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: DocumentSanitizeLayout.documentTabBarHeight)
    }
}

private struct DocumentTabButton: View {
    let title: String
    let status: DocumentBatchTabStatus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: OFSpacing.sm) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .ofText : .ofTextMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                DocumentTabStatusIndicator(status: status)
            }
            .padding(.horizontal, OFSpacing.md)
            .padding(.vertical, OFSpacing.sm)
            .background(isSelected ? Color.ofBg2 : Color.ofBg1)
            .cornerRadius(OFRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.md)
                    .stroke(isSelected ? Color.ofBorder2 : Color.ofBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        "\(title), \(status.accessibilityDescription)"
    }
}

private struct DocumentTabStatusIndicator: View {
    let status: DocumentBatchTabStatus

    var body: some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "circle")
                    .foregroundColor(.ofTextMuted)
            case .analyzing:
                ProgressView()
                    .controlSize(.small)
            case .safe:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.ofGreenText)
            case let .findings(count):
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.ofAmberText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.ofAmberDim)
                    .clipShape(Capsule())
            case .error, .tooLarge:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.ofRedText)
            }
        }
        .font(.system(size: 11))
        .frame(minWidth: 16, minHeight: 16)
    }
}

private extension DocumentBatchTabStatus {
    var accessibilityDescription: String {
        switch self {
        case .pending:
            return OffsendStrings.documentSanitizeTabStatusPending
        case .analyzing:
            return OffsendStrings.documentSanitizeAnalyzing
        case .safe:
            return OffsendStrings.documentSanitizeSafeTitle
        case let .findings(count):
            return OffsendStrings.documentSanitizeTabStatusFindings(count)
        case .error:
            return OffsendStrings.documentSanitizeErrorTitle
        case .tooLarge:
            return OffsendStrings.documentSanitizeFileTooLargeProNote
        }
    }
}
