import SwiftUI

public struct OFIconTile: View {
    private let systemName: String
    private let tint: Color
    private let size: CGFloat
    private let iconSize: CGFloat
    private let glow: Bool

    public init(
        systemName: String,
        tint: Color = .ofBlue,
        size: CGFloat = 36,
        iconSize: CGFloat = 16,
        glow: Bool = false
    ) {
        self.systemName = systemName
        self.tint = tint
        self.size = size
        self.iconSize = iconSize
        self.glow = glow
    }

    public var body: some View {
        ZStack {
            if glow {
                RoundedRectangle(cornerRadius: size * 0.27)
                    .fill(tint.opacity(0.18))
                    .frame(width: size + 8, height: size + 8)
                    .blur(radius: 6)
            }

            RoundedRectangle(cornerRadius: size * 0.27)
                .fill(tint.opacity(0.15))
                .frame(width: size, height: size)

            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(tint)
        }
        .frame(width: size, height: size)
    }
}
