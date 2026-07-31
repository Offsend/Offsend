import AppKit
import SwiftUI

public struct OFAppTile: View {
    private let name: String
    private let bundleIdentifier: String?
    private let size: CGFloat

    public init(name: String, bundleIdentifier: String? = nil, size: CGFloat = 28) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.size = size
    }

    public var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size / 4.5))
            } else {
                letterTile
            }
        }
        .frame(width: size, height: size)
    }

    private var appIcon: NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var letterTile: some View {
        let hue = Double((Int(name.unicodeScalars.first?.value ?? 65) * 37) % 360)
        return ZStack {
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
    }
}
