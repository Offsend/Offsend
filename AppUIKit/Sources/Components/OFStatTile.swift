import SwiftUI

/// Footnote shown under the big value of an `OFStatTile`.
public enum OFStatTileAccessory: Equatable {
    case none
    /// Muted footnote, e.g. "none ignored" or "0 of 1 · free plan".
    case caption(String)
    /// Blue accent chip with a leading dot, e.g. "+9 with Pro".
    case proUpsell(String)
}

/// Compact statistics card: header icon + label, large value, optional footnote.
public struct OFStatTile: View {
    private let icon: String
    private let label: String
    private let value: String
    private let accessory: OFStatTileAccessory

    public init(
        icon: String,
        label: String,
        value: String,
        accessory: OFStatTileAccessory = .none
    ) {
        self.icon = icon
        self.label = label
        self.value = value
        self.accessory = accessory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ofTextMuted)
                    .frame(height: 13, alignment: .center)

                Text(label.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.6)
                    .foregroundColor(.ofTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 28, alignment: .topLeading)

            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .fontWidth(.condensed)
                .foregroundColor(.ofText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            accessoryView
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .fill(Color.ofBg1)
                .overlay(
                    RoundedRectangle(cornerRadius: OFRadius.md)
                        .stroke(Color.ofBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .caption(let text):
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.ofTextMuted)
                .lineLimit(1)
                .truncationMode(.tail)
        case .proUpsell(let text):
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.ofBlue)
                    .frame(width: 5, height: 5)
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ofBlueText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.ofBlueDim))
        }
    }
}
