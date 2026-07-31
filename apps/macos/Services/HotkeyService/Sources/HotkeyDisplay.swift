import AppKit
import Foundation
import KeyboardShortcuts
import SwiftUI

public enum HotkeyKind {
    case safePaste
    case restorePlaceholders
}

public struct HotkeyMenuKeyEquivalent {
    public let key: String
    public let modifiers: NSEvent.ModifierFlags
}

public enum HotkeyDisplay {
    @MainActor
    public static func shortcut(for kind: HotkeyKind) -> KeyboardShortcuts.Shortcut? {
        shortcut(for: name(for: kind))
    }

    @MainActor
    public static func shortcut(for name: KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: name) ?? defaultShortcut(for: name)
    }

    @MainActor
    public static func string(for kind: HotkeyKind) -> String {
        shortcut(for: kind)?.description ?? ""
    }

    @MainActor
    public static var safePaste: String {
        string(for: .safePaste)
    }

    @MainActor
    public static var restorePlaceholders: String {
        string(for: .restorePlaceholders)
    }

    @MainActor
    public static func menuKeyEquivalent(for kind: HotkeyKind) -> HotkeyMenuKeyEquivalent? {
        guard let shortcut = shortcut(for: kind),
              let key = shortcut.nsMenuItemKeyEquivalent else {
            return nil
        }
        return HotkeyMenuKeyEquivalent(key: key, modifiers: shortcut.modifiers)
    }

    @MainActor
    public static func swiftUIKeyboardShortcut(for kind: HotkeyKind) -> KeyboardShortcut? {
        guard let shortcut = shortcut(for: kind) else {
            return nil
        }
        return swiftUIKeyboardShortcut(from: shortcut)
    }

    @MainActor
    private static func name(for kind: HotkeyKind) -> KeyboardShortcuts.Name {
        switch kind {
        case .safePaste:
            return .safePaste
        case .restorePlaceholders:
            return .restorePlaceholders
        }
    }

    @MainActor
    private static func defaultShortcut(for name: KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? {
        switch name {
        case .safePaste:
            return KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift])
        case .restorePlaceholders:
            return KeyboardShortcuts.Shortcut(.r, modifiers: [.command, .shift])
        default:
            return nil
        }
    }

    @MainActor
    private static func swiftUIKeyboardShortcut(from shortcut: KeyboardShortcuts.Shortcut) -> KeyboardShortcut? {
        var modifiers = EventModifiers()
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }

        guard let keyEquivalent = shortcut.nsMenuItemKeyEquivalent,
              let character = keyEquivalent.first else {
            return nil
        }

        if #available(macOS 12.0, *) {
            return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers, localization: .custom)
        }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
}

public extension Notification.Name {
    static let keyboardShortcutDidChange = Self("KeyboardShortcuts_shortcutByNameDidChange")
}
