import Foundation
import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    static let safePaste = Self("safePaste", default: .init(.v, modifiers: [.command, .shift]))
    static let restorePlaceholders = Self("restorePlaceholders", default: .init(.r, modifiers: [.command, .shift]))
}

public final class HotkeyService {
    private var safePasteHandler: (() -> Void)?
    private var restoreHandler: (() -> Void)?

    public init() {}

    public func register(safePaste: @escaping () -> Void, restore: @escaping () -> Void) {
        safePasteHandler = safePaste
        restoreHandler = restore

        KeyboardShortcuts.onKeyUp(for: .safePaste) { [weak self] in
            let handler = self?.safePasteHandler
            DispatchQueue.main.async {
                handler?()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .restorePlaceholders) { [weak self] in
            let handler = self?.restoreHandler
            DispatchQueue.main.async {
                handler?()
            }
        }
    }

    public func resetDefaults() {
        KeyboardShortcuts.reset(.safePaste)
        KeyboardShortcuts.reset(.restorePlaceholders)
    }
}
