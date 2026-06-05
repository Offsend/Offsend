import AppUIKit
import SwiftUI

struct DocumentSafeResultView: View {
    var body: some View {
        VStack(spacing: OFSpacing.md) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.ofGreen)

            Text(OffsendStrings.documentSanitizeSafeTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.ofText)
                .multilineTextAlignment(.center)

            Text(OffsendStrings.documentSanitizeSafeSubtitle)
                .font(.system(size: 13))
                .foregroundColor(.ofGreenText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ofGreenDim.opacity(0.55))
        .cornerRadius(OFRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.lg)
                .stroke(Color.ofGreen.opacity(0.45), lineWidth: 1)
        )
    }
}
