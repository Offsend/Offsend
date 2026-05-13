import SwiftUI

public enum OFButtonVariant {
    case primary
    case outline
    case ghost
    case danger
}

public struct OFButton: View {
    private let title: String
    private let variant: OFButtonVariant
    private let icon: String?
    private let small: Bool
    private let disabled: Bool
    private let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    public init(
        title: String,
        variant: OFButtonVariant,
        icon: String? = nil,
        small: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.icon = icon
        self.small = small
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: small ? 11 : 12, weight: .medium))
                }

                Text(title)
                    .font(.system(size: small ? 12 : 13, weight: .medium))
            }
            .foregroundColor(disabled ? foregroundColor.opacity(0.45) : foregroundColor)
            .padding(.horizontal, small ? 10 : 14)
            .padding(.vertical, small ? 5 : 7)
            .background(disabled ? backgroundColor.opacity(0.45) : backgroundColor)
            .cornerRadius(OFRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.sm)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary:
            return isHovered ? .ofBlueHover : .ofBlue
        case .danger:
            return isHovered ? .ofRedHover : .ofRed
        case .outline:
            return isHovered ? .ofBg3 : .ofBg2
        case .ghost:
            return isHovered ? .ofBg3 : .clear
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .danger:
            return .white
        case .outline:
            return .ofText
        case .ghost:
            return .ofTextSub
        }
    }

    private var borderColor: Color {
        switch variant {
        case .outline, .ghost:
            return .ofBorder2
        case .primary, .danger:
            return .clear
        }
    }
}
