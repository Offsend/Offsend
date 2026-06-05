import AppUIKit
import SwiftUI

struct DirectoryCheckWorkingOverlay: View {
    let isApplyingFix: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            VStack(spacing: OFSpacing.md) {
                ProgressView()
                    .controlSize(.regular)
                Text(isApplyingFix ? OffsendStrings.directoryCheckApplyingFix : OffsendStrings.directoryCheckAuditing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.ofText)
            }
            .padding(OFSpacing.md)
            .background(Color.ofBg2)
            .cornerRadius(OFRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.lg)
                    .stroke(Color.ofBorder, lineWidth: 1)
            )
        }
    }
}
