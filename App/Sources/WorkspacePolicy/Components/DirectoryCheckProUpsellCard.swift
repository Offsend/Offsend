import AppUIKit
import SwiftUI

struct DirectoryCheckProUpsellCard: View {
    let onOpenCheckout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Label(OffsendStrings.directoryCheckProUpsellTitle, systemImage: "crown.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.ofBlue)

            Text(OffsendStrings.directoryCheckProUpsellBody)
                .font(.system(size: 12))
                .foregroundColor(.ofTextSub)
                .fixedSize(horizontal: false, vertical: true)

            OFButton(
                title: OffsendStrings.directoryCheckProUpsellCta,
                variant: .outline,
                icon: "arrow.up.right",
                small: true,
                action: onOpenCheckout
            )
        }
        .padding(OFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBorder, lineWidth: 1)
        )
    }
}
