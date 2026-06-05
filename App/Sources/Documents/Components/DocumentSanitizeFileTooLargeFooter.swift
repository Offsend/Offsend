import AppUIKit
import SwiftUI

struct DocumentSanitizeFileTooLargeFooter: View {
    let isBusy: Bool
    let onBuyPro: () -> Void

    var body: some View {
        OFPinnedActionFooter(
            statusText: OffsendStrings.documentSanitizeFileTooLargeProNote,
            buttonTitle: OffsendStrings.directoryCheckBuyPro,
            buttonIcon: "crown.fill",
            buttonDisabled: isBusy,
            action: onBuyPro
        )
    }
}
