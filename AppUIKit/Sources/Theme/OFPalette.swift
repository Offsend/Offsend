import AppKit
import SwiftUI

public struct OFPalette {
    public let bg0, bg1, bg2, bg3: Color
    public let card: Color
    public let border, border2: Color
    public let blue, blueHover, blueDeep, blueDim, blueText: Color
    public let amber, amberDim, amberText: Color
    public let red, redHover, redDim, redText: Color
    public let green, greenDim, greenText: Color
    public let text, textSub, textMuted: Color

    public static let dark = OFPalette(
        bg0: Color(hex: "#0E1014"),
        bg1: Color(hex: "#161A20"),
        bg2: Color(hex: "#1D222A"),
        bg3: Color(hex: "#252B35"),
        card: Color(hex: "#191E26"),
        border: Color.white.opacity(0.06),
        border2: Color.white.opacity(0.12),
        blue: Color(hex: "#3D8EF0"),
        blueHover: Color(hex: "#5BA3F5"),
        blueDeep: Color(hex: "#1F5FBE"),
        blueDim: Color(hex: "#3D8EF0").opacity(0.18),
        blueText: Color(hex: "#8BBDF5"),
        amber: Color(hex: "#E8A838"),
        amberDim: Color(hex: "#E8A838").opacity(0.16),
        amberText: Color(hex: "#F5CC80"),
        red: Color(hex: "#E04F3A"),
        redHover: Color(hex: "#E86655"),
        redDim: Color(hex: "#E04F3A").opacity(0.18),
        redText: Color(hex: "#F08A7A"),
        green: Color(hex: "#34C97A"),
        greenDim: Color(hex: "#34C97A").opacity(0.16),
        greenText: Color(hex: "#6FDBA4"),
        text: Color(hex: "#EEF0F4"),
        textSub: Color(hex: "#8890A0"),
        textMuted: Color(hex: "#555E6E")
    )

    public static let light = OFPalette(
        bg0: Color(hex: "#F6F7FA"),
        bg1: Color(hex: "#FFFFFF"),
        bg2: Color(hex: "#F0F1F5"),
        bg3: Color(hex: "#E3E5EC"),
        card: Color(hex: "#FFFFFF"),
        border: Color.black.opacity(0.07),
        border2: Color.black.opacity(0.14),
        blue: Color(hex: "#2563EB"),
        blueHover: Color(hex: "#1E40AF"),
        blueDeep: Color(hex: "#1E3A8A"),
        blueDim: Color(hex: "#2563EB").opacity(0.10),
        blueText: Color(hex: "#1D4ED8"),
        amber: Color(hex: "#B45309"),
        amberDim: Color(hex: "#D97706").opacity(0.12),
        amberText: Color(hex: "#92400E"),
        red: Color(hex: "#DC2626"),
        redHover: Color(hex: "#B91C1C"),
        redDim: Color(hex: "#DC2626").opacity(0.10),
        redText: Color(hex: "#991B1B"),
        green: Color(hex: "#16A34A"),
        greenDim: Color(hex: "#16A34A").opacity(0.12),
        greenText: Color(hex: "#166534"),
        text: Color(hex: "#111827"),
        textSub: Color(hex: "#4B5563"),
        textMuted: Color(hex: "#6B7280")
    )
}

/// Appearance of the settings window chrome (custom palette + `preferredColorScheme`). `auto` follows the system light/dark mode.
public enum OFSettingsChromeAppearance: String, CaseIterable, Hashable, Codable {
    case light
    case dark
    case auto

    public static let appStorageKey = "offsend.settings.chromeAppearance"
    public static let legacyChromeDarkBoolKey = "offsend.settings.chromeDark"

    /// Resolved system light/dark, **not** SwiftUI `Environment.colorScheme` — it can stay `.light` after switching from forced light to **Auto** if `preferredColorScheme` was `nil`.
    public static func resolvedSystemColorScheme() -> ColorScheme {
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
            return .dark
        }
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .dark
        }
        return .light
    }

    public func resolvedPalette() -> OFPalette {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return Self.resolvedSystemColorScheme() == .dark ? .dark : .light
        }
    }

    /// Always returns a concrete scheme so the window updates reliably when leaving forced light/dark for **Auto**.
    public var preferredColorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return Self.resolvedSystemColorScheme()
        }
    }

    /// Copies the legacy boolean `chromeDark` into `appStorageKey` once, so existing installs keep their choice; new installs default to `.auto` via `@AppStorage` default.
    public static func migrateFromLegacyUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: appStorageKey) == nil else { return }
        guard defaults.object(forKey: legacyChromeDarkBoolKey) != nil else { return }
        let raw = defaults.bool(forKey: legacyChromeDarkBoolKey) ? Self.dark.rawValue : Self.light.rawValue
        defaults.set(raw, forKey: appStorageKey)
    }
}

private struct OFPaletteKey: EnvironmentKey {
    static let defaultValue: OFPalette = .dark
}

public extension EnvironmentValues {
    var ofPalette: OFPalette {
        get { self[OFPaletteKey.self] }
        set { self[OFPaletteKey.self] = newValue }
    }
}

private struct OFSystemAppearanceRefreshModifier: ViewModifier {
    @Binding var revision: Int

    func body(content: Content) -> some View {
        content
            .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))) { _ in
                revision += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                revision += 1
            }
    }
}

extension View {
    /// Bumps `revision` when macOS switches or re-resolves light/dark so **Auto** chrome and `Color.of*` refresh.
    public func ofRefreshOnSystemAppearanceChange(_ revision: Binding<Int>) -> some View {
        modifier(OFSystemAppearanceRefreshModifier(revision: revision))
    }
}
