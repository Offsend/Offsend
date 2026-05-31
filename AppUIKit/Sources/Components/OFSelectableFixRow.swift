import SwiftUI

public struct OFSelectableFixRow: View {
    private let badgeStyle: OFStatusBadgeStyle
    private let title: String
    private let toolName: String?
    private let description: String
    private let isSelected: Bool
    private let isEnabled: Bool
    private let isProLocked: Bool
    private let action: () -> Void

    public init(
        badgeStyle: OFStatusBadgeStyle,
        title: String,
        toolName: String? = nil,
        description: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        isProLocked: Bool = false,
        action: @escaping () -> Void
    ) {
        self.badgeStyle = badgeStyle
        self.title = title
        self.toolName = toolName
        self.description = description
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isProLocked = isProLocked
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: OFSpacing.md) {
                OFStatusBadge(style: badgeStyle, compact: true)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(isEnabled ? .ofText : .ofTextMuted)

                        if let toolName {
                            Text(toolName)
                                .font(.system(size: 12))
                                .foregroundColor(.ofTextMuted)
                        }

                        if isProLocked {
                            Text("PRO")
                                .font(.system(size: 9, weight: .bold))
                                .kerning(0.5)
                                .foregroundColor(.ofBlue)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.ofBlueDim)
                                .clipShape(Capsule())
                        }
                    }

                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.ofTextSub)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isEnabled ? (isSelected ? .ofBlue : .ofTextMuted) : .ofTextMuted.opacity(0.35))
                    .padding(.top, 1)
            }
            .padding(.horizontal, OFSpacing.md)
            .padding(.vertical, 12)
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
