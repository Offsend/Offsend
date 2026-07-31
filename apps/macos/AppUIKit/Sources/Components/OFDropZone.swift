import SwiftUI

public struct OFDropZone: View {
    private let title: String
    private let hint: String
    private let isTargeted: Bool
    private let fillsAvailableSpace: Bool
    private let action: () -> Void

    public init(
        title: String,
        hint: String,
        isTargeted: Bool,
        fillsAvailableSpace: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.hint = hint
        self.isTargeted = isTargeted
        self.fillsAvailableSpace = fillsAvailableSpace
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: OFSpacing.md) {
                if fillsAvailableSpace {
                    Spacer(minLength: 0)
                }

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(isTargeted ? .ofBlue : .ofTextMuted)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.ofText)

                Text(hint)
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
                    .multilineTextAlignment(.center)

                if fillsAvailableSpace {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: fillsAvailableSpace ? .infinity : nil)
            .padding(.vertical, fillsAvailableSpace ? OFSpacing.xl : 48)
            .padding(.horizontal, OFSpacing.lg)
            .background(isTargeted ? Color.ofBlueDim.opacity(0.35) : Color.ofBg2.opacity(0.5))
            .cornerRadius(OFRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.lg)
                    .stroke(
                        isTargeted ? Color.ofBlue : Color.ofBorder2,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
