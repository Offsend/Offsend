import SwiftUI

public struct OFSettingsRow<Content: View>: View {
    private let label: String
    private let hint: String?
    private let alignTop: Bool
    private let content: Content
    @Environment(\.ofPalette) private var palette

    public init(label: String, hint: String? = nil, alignTop: Bool = false, @ViewBuilder control: () -> Content) {
        self.label = label
        self.hint = hint
        self.alignTop = alignTop
        self.content = control()
    }

    public var body: some View {
        HStack(alignment: alignTop ? .top : .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.text)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundColor(palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            content
        }
        .padding(.vertical, 12)
    }
}

public struct OFSettingsGroup<Content: View>: View {
    private let title: String
    private let hint: String?
    private let content: Content
    @Environment(\.ofPalette) private var palette

    public init(title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.hint = hint
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(palette.textMuted)
                .padding(.leading, 2)
            if let hint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSub)
                    .padding(.leading, 2)
                    .frame(maxWidth: 520, alignment: .leading)
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(palette.card)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
                )
        }
        .padding(.bottom, 24)
    }
}

public struct OFSettingsGroupDivider: View {
    @Environment(\.ofPalette) private var palette

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: 1)
    }
}
