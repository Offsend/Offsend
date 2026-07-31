import SwiftUI

public struct OFKeyCap: View {
    private let text: String
    @Environment(\.ofPalette) private var palette

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(palette.text)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(palette.bg2)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.border2, lineWidth: 1))
            )
    }
}
