import SwiftUI

public struct OFPinnedActionFooter: View {
    private let statusText: String
    private let buttonTitle: String
    private let buttonIcon: String
    private let buttonDisabled: Bool
    private let action: () -> Void

    public init(
        statusText: String,
        buttonTitle: String,
        buttonIcon: String = "wand.and.stars",
        buttonDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.statusText = statusText
        self.buttonTitle = buttonTitle
        self.buttonIcon = buttonIcon
        self.buttonDisabled = buttonDisabled
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 0) {
            OFDivider()

            HStack(spacing: OFSpacing.md) {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextMuted)
                    .lineLimit(1)

                Spacer(minLength: 0)

                OFButton(
                    title: buttonTitle,
                    variant: .primary,
                    icon: buttonIcon,
                    disabled: buttonDisabled,
                    action: action
                )
            }
            .padding(.horizontal, OFSpacing.md)
            .padding(.vertical, OFSpacing.md)
            .background(Color.ofBg0)
        }
    }
}
