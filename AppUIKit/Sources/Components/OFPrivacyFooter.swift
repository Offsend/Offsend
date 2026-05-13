import SwiftUI

public struct OFPrivacyFooter: View {
    private let hotkey: String?
    private let text: String

    public init(
        hotkey: String? = nil,
        text: String = AppUIKitStrings.privacyFooterDefault
    ) {
        self.hotkey = hotkey
        self.text = text
    }

    public var body: some View {
        HStack {
            Circle()
                .fill(Color.ofGreen)
                .frame(width: 5, height: 5)

            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.ofTextMuted)

            Spacer()

            if let hotkey {
                KbdBadge(text: hotkey)
            }
        }
        .padding(.horizontal, OFSpacing.xl)
        .padding(.vertical, 8)
        .background(Color.ofBg0)
    }
}
