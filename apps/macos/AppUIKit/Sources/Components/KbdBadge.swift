import SwiftUI

public struct KbdBadge: View {
    private let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.ofTextSub)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.ofBg3)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.ofBorder2, lineWidth: 1)
            )
    }
}
