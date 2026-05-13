import SwiftUI

#if os(macOS)
import AppKit
#endif

private enum OFColorFactory {
    static func color(light: String, dark: String) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return nsColor(hex: bestMatch == .darkAqua ? dark : light)
        })
        #else
        return Color(hex: dark)
        #endif
    }

    #if os(macOS)
    private static func nsColor(hex: String) -> NSColor {
        let components = rgbComponents(hex: hex)
        return NSColor(
            srgbRed: CGFloat(components.red),
            green: CGFloat(components.green),
            blue: CGFloat(components.blue),
            alpha: 1
        )
    }
    #endif

    fileprivate static func rgbComponents(hex: String) -> (red: Double, green: Double, blue: Double) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255
        return (red, green, blue)
    }
}

public extension Color {
    init(hex: String) {
        let components = OFColorFactory.rgbComponents(hex: hex)
        self.init(.sRGB, red: components.red, green: components.green, blue: components.blue, opacity: 1)
    }

    static let ofBg0 = OFColorFactory.color(light: "#EDEEF2", dark: "#0E1014")
    static let ofBg1 = OFColorFactory.color(light: "#FAFBFC", dark: "#161A20")
    static let ofBg2 = OFColorFactory.color(light: "#F0F1F5", dark: "#1D222A")
    static let ofBg3 = OFColorFactory.color(light: "#E3E5EC", dark: "#252B35")

    static let ofBorder = OFColorFactory.color(light: "#D9DDE6", dark: "#2B313C")
    static let ofBorder2 = OFColorFactory.color(light: "#CBD1DD", dark: "#3A4250")

    static let ofBlue = OFColorFactory.color(light: "#2563EB", dark: "#3D8EF0")
    static let ofBlueHover = OFColorFactory.color(light: "#1D4ED8", dark: "#5BA3F5")
    static let ofBlueDim = OFColorFactory.color(light: "#DBEAFE", dark: "#172A45")
    static let ofBlueText = OFColorFactory.color(light: "#1D4ED8", dark: "#8BBDF5")

    static let ofAmber = OFColorFactory.color(light: "#B45309", dark: "#E8A838")
    static let ofAmberHover = OFColorFactory.color(light: "#92400E", dark: "#F0B84A")
    static let ofAmberDim = OFColorFactory.color(light: "#FEF3C7", dark: "#3B2C12")
    static let ofAmberText = OFColorFactory.color(light: "#92400E", dark: "#F5CC80")

    static let ofRed = OFColorFactory.color(light: "#DC2626", dark: "#E04F3A")
    static let ofRedHover = OFColorFactory.color(light: "#B91C1C", dark: "#E86655")
    static let ofRedDim = OFColorFactory.color(light: "#FEE2E2", dark: "#3A1D1C")
    static let ofRedText = OFColorFactory.color(light: "#991B1B", dark: "#F08A7A")

    static let ofGreen = OFColorFactory.color(light: "#16A34A", dark: "#34C97A")
    static let ofGreenDim = OFColorFactory.color(light: "#DCFCE7", dark: "#143321")
    static let ofGreenText = OFColorFactory.color(light: "#166534", dark: "#6FDBA4")

    static let ofText = OFColorFactory.color(light: "#111827", dark: "#EEF0F4")
    static let ofTextSub = OFColorFactory.color(light: "#4B5563", dark: "#8890A0")
    static let ofTextMuted = OFColorFactory.color(light: "#6B7280", dark: "#555E6E")
}
