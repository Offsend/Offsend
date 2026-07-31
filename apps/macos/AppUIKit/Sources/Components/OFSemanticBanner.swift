import SwiftUI

public enum OFSemanticBannerStyle {
    case success
    case info
    case warning

    var accentColor: Color {
        switch self {
        case .success:
            return .ofGreen
        case .info:
            return .ofBlue
        case .warning:
            return .ofAmber
        }
    }

    var dimColor: Color {
        switch self {
        case .success:
            return .ofGreenDim
        case .info:
            return .ofBlueDim
        case .warning:
            return .ofAmberDim
        }
    }

    var textColor: Color {
        switch self {
        case .success:
            return .ofGreenText
        case .info:
            return .ofBlueText
        case .warning:
            return .ofAmberText
        }
    }
}

public struct OFSemanticBanner: View {
    private let style: OFSemanticBannerStyle
    private let icon: String
    private let title: String
    private let subtitle: String

    public init(
        style: OFSemanticBannerStyle,
        icon: String,
        title: String,
        subtitle: String
    ) {
        self.style = style
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(alignment: .top, spacing: OFSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(style.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ofText)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(style.textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(OFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.dimColor.opacity(0.55))
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(style.accentColor.opacity(0.45), lineWidth: 1)
        )
    }
}
