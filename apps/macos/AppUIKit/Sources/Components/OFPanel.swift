import SwiftUI

public struct OFPanel<Content: View>: View {
    private let width: CGFloat?
    private let content: Content

    public init(width: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(Color.ofBg1)
            .cornerRadius(OFRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.lg)
                    .stroke(Color.ofBorder2, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 32, x: 0, y: 16)
            .frame(width: width)
    }
}
