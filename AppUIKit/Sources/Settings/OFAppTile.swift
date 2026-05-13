import SwiftUI

public struct OFAppTile: View {
    private let name: String
    private let size: CGFloat

    public init(name: String, size: CGFloat = 28) {
        self.name = name
        self.size = size
    }

    public var body: some View {
        let hue = Double((Int(name.unicodeScalars.first?.value ?? 65) * 37) % 360)
        ZStack {
            RoundedRectangle(cornerRadius: size / 4.5)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: hue / 360, saturation: 0.55, brightness: 0.85),
                            Color(hue: hue / 360, saturation: 0.75, brightness: 0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(String(name.prefix(1)))
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}
