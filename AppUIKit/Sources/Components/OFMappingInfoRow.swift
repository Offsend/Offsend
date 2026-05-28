import SwiftUI

public struct OFMappingInfoRow: View {
    private let restoreHotkey: String

    public init(restoreHotkey: String) {
        self.restoreHotkey = restoreHotkey
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key")
                .font(.system(size: 12))
                .foregroundColor(.ofTextMuted)

            Text(AppUIKitStrings.mappingInfoSavedTTL)
                .font(.system(size: 11))
                .foregroundColor(.ofTextMuted)

            Spacer()

            HStack(spacing: 4) {
                Text(AppUIKitStrings.mappingInfoRestoreWith)
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextSub)

                KbdBadge(text: restoreHotkey)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.sm)
    }
}
