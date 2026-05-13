import SwiftUI

public enum OFCompactButtonVariant {
    case primary
    case primaryDanger
    case outline
    case ghost
    case dangerGhost
}

public struct OFCompactButton: View {
    private let title: String
    private let icon: String?
    private let variant: OFCompactButtonVariant
    private let small: Bool
    private let action: () -> Void
    @State private var hovered = false
    @Environment(\.ofPalette) private var palette

    public init(
        title: String,
        icon: String? = nil,
        variant: OFCompactButtonVariant = .primary,
        small: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.small = small
        self.action = action
    }

    private var background: Color {
        switch variant {
        case .primary:
            return hovered ? palette.blueHover : palette.blue
        case .primaryDanger:
            return hovered ? palette.redHover : palette.red
        case .outline:
            return hovered ? palette.bg2 : palette.bg1
        case .ghost:
            return hovered ? palette.bg2 : .clear
        case .dangerGhost:
            return hovered ? palette.redDim : .clear
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary, .primaryDanger:
            return .white
        case .outline:
            return palette.text
        case .ghost:
            return palette.textSub
        case .dangerGhost:
            return palette.redText
        }
    }

    private var stroke: Color {
        switch variant {
        case .outline:
            return palette.border2
        case .dangerGhost:
            return palette.redDim
        default:
            return .clear
        }
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: small ? 10 : 11))
                }
                Text(title)
                    .font(.system(size: small ? 11 : 12, weight: .medium))
            }
            .foregroundColor(foreground)
            .padding(.horizontal, small ? 10 : 14)
            .padding(.vertical, small ? 5 : 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(background)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(stroke, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
