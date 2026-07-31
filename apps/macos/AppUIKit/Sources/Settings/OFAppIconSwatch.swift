import SwiftUI

public enum OFAlternateAppIcon: String, CaseIterable, Identifiable {
    case classic
    case midnight
    case sand
    case forest
    case mono

    public var id: String { rawValue }
}

public struct OFAppIconSwatch: View {
    private let variant: OFAlternateAppIcon
    private let selected: Bool
    private let action: () -> Void
    @Environment(\.ofPalette) private var palette

    public init(variant: OFAlternateAppIcon, selected: Bool, action: @escaping () -> Void) {
        self.variant = variant
        self.selected = selected
        self.action = action
    }

    private var gradient: LinearGradient {
        switch variant {
        case .classic:
            return LinearGradient(colors: [palette.blue, palette.blueDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .midnight:
            return LinearGradient(colors: [Color(hex: "#2E3850"), Color(hex: "#0E1014")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .sand:
            return LinearGradient(colors: [Color(hex: "#F1B872"), Color(hex: "#C76A3D")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .forest:
            return LinearGradient(colors: [palette.green, Color(hex: "#1F5C3B")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .mono:
            return LinearGradient(colors: [Color(hex: "#F4F5F8"), Color(hex: "#C9CCD3")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var shieldFill: Color {
        switch variant {
        case .midnight:
            return palette.blue
        case .mono:
            return Color(hex: "#202734")
        default:
            return .white
        }
    }

    private var checkColor: Color {
        variant == .mono ? Color(hex: "#202734") : Color(hex: "#1F2A44")
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(gradient)
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.25), lineWidth: 0.5))
                Image(systemName: "shield.fill")
                    .font(.system(size: 18))
                    .foregroundColor(shieldFill)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(checkColor)
                    .offset(y: 1)
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(selected ? palette.blue : .clear, lineWidth: 2)
                    .padding(-3)
            )
        }
        .buttonStyle(.plain)
    }
}
