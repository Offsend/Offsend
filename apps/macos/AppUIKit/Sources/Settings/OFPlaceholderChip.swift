import SwiftUI

public struct OFPlaceholderChip: View {
    private let text: String
    @Environment(\.ofPalette) private var palette

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(palette.blueText)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(palette.blueDim)
            .cornerRadius(3)
    }
}
