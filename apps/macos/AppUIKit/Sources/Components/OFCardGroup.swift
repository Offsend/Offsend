import SwiftUI

public struct OFCardGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBorder, lineWidth: 1)
        )
    }
}

public struct OFCardGroupDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Color.ofBorder)
            .frame(height: 1)
    }
}

public struct OFCardRow<Trailing: View>: View {
    private let icon: String
    private let iconTint: Color
    private let title: String
    private let subtitle: String?
    private let subtitleTint: Color?
    private let highlighted: Bool
    private let trailing: Trailing

    public init(
        icon: String,
        iconTint: Color = .ofTextMuted,
        title: String,
        subtitle: String? = nil,
        subtitleTint: Color? = nil,
        highlighted: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.subtitleTint = subtitleTint
        self.highlighted = highlighted
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: OFSpacing.md) {
            OFIconTile(systemName: icon, tint: iconTint, size: 32, iconSize: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ofText)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(subtitleTint ?? .ofTextSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(.horizontal, OFSpacing.md)
        .padding(.vertical, 12)
        .background(highlighted ? Color.ofBlueDim.opacity(0.45) : Color.clear)
    }
}

public extension OFCardRow where Trailing == EmptyView {
    init(
        icon: String,
        iconTint: Color = .ofTextMuted,
        title: String,
        subtitle: String? = nil,
        subtitleTint: Color? = nil,
        highlighted: Bool = false
    ) {
        self.init(
            icon: icon,
            iconTint: iconTint,
            title: title,
            subtitle: subtitle,
            subtitleTint: subtitleTint,
            highlighted: highlighted
        ) {
            EmptyView()
        }
    }
}
