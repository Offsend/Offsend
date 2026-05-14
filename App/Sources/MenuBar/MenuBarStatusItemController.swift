import AppKit
import StorageCore

@MainActor
final class MenuBarStatusItemController: NSObject {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    private let menu = NSMenu()
    private var safePaste: (() -> Void)?
    private var showClipboardStatus: (() -> Void)?
    private var restore: (() -> Void)?
    private var refreshBeforeOpen: (() -> Void)?
    private var toggleProtection: (() -> Void)?
    private var toggleClipboardMonitoring: (() -> Void)?
    private var openOnboarding: (() -> Void)?
    private var openSettings: (() -> Void)?
    private var checkForUpdates: (() -> Void)?

    override init() {
        super.init()
        statusItem.menu = menu
        menu.delegate = self
        if let button = statusItem.button {
            button.imageScaling = .scaleProportionallyDown
        }
    }

    func configureActions(
        safePaste: @escaping () -> Void,
        showClipboardStatus: @escaping () -> Void,
        restore: @escaping () -> Void,
        refreshBeforeOpen: @escaping () -> Void,
        toggleProtection: @escaping () -> Void,
        toggleClipboardMonitoring: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void
    ) {
        self.safePaste = safePaste
        self.showClipboardStatus = showClipboardStatus
        self.restore = restore
        self.refreshBeforeOpen = refreshBeforeOpen
        self.toggleProtection = toggleProtection
        self.toggleClipboardMonitoring = toggleClipboardMonitoring
        self.checkForUpdates = checkForUpdates
    }

    func configureWindowActions(
        openOnboarding: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.openOnboarding = openOnboarding
        self.openSettings = openSettings
    }

    func update(
        icon: NSImage,
        iconTint: NSColor?,
        settings: AppSettings,
        clipboardStatusTitle: String,
        isClipboardStatusActionEnabled: Bool,
        lastStatusMessage: String
    ) {
        if let button = statusItem.button {
            button.contentTintColor = nil
            let image = Self.statusBarMenuImage(from: icon, tint: iconTint)
            if button.image !== image {
                button.image = image
            }
        }

        rebuildMenu(
            settings: settings,
            clipboardStatusTitle: clipboardStatusTitle,
            isClipboardStatusActionEnabled: isClipboardStatusActionEnabled,
            lastStatusMessage: lastStatusMessage
        )
    }

    private static let statusBarIconLayoutSize = NSSize(width: 18, height: 18)

    private struct CompositeCacheKey: Hashable {
        enum DotTint: Hashable {
            case label
            case orange
            case red
        }

        let dot: DotTint
        let appearanceName: NSAppearance.Name

        init(dotColor: NSColor, appearance: NSAppearance) {
            appearanceName = appearance.name
            if dotColor == .systemOrange {
                dot = .orange
            } else if dotColor == .systemRed {
                dot = .red
            } else {
                dot = .label
            }
        }
    }

    private static var compositeImageCache: [CompositeCacheKey: NSImage] = [:]

    static func compositeStatusBarIcon(base: NSImage, mask: NSImage, dotColor: NSColor) -> NSImage {
        let key = CompositeCacheKey(dotColor: dotColor, appearance: NSApp.effectiveAppearance)
        if let cached = compositeImageCache[key] {
            return cached
        }

        let layout = statusBarIconLayoutSize
        guard let baseCopy = base.copy() as? NSImage,
              let maskCopy = mask.copy() as? NSImage else {
            return base
        }
        baseCopy.size = layout
        maskCopy.size = layout
        baseCopy.isTemplate = true
        maskCopy.isTemplate = true

        let fullRect = NSRect(origin: .zero, size: layout)
        let dotTinted = NSImage(size: layout, flipped: false) { _ in
            dotColor.set()
            fullRect.fill()
            maskCopy.draw(in: fullRect, from: fullRect, operation: .destinationIn, fraction: 1)
            return true
        }
        dotTinted.isTemplate = false

        let composite = NSImage(size: layout, flipped: false) { _ in
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                NSColor.labelColor.set()
                fullRect.fill()
                baseCopy.draw(in: fullRect, from: fullRect, operation: .destinationIn, fraction: 1)
            }
            dotTinted.draw(in: fullRect, from: fullRect, operation: .sourceOver, fraction: 1)
            return true
        }
        composite.isTemplate = false

        compositeImageCache[key] = composite
        return composite
    }

    private static func statusBarMenuImage(from source: NSImage, tint: NSColor?) -> NSImage {
        let layout = statusBarIconLayoutSize
        if tint == nil,
           source.size == layout,
           !source.isTemplate {
            return source
        }

        guard let copy = source.copy() as? NSImage else {
            return source
        }
        copy.size = layout

        if let tint {
            copy.isTemplate = true
            let colored = NSImage(size: layout, flipped: false) { rect in
                tint.set()
                rect.fill()
                let src = NSRect(origin: .zero, size: layout)
                copy.draw(in: rect, from: src, operation: .destinationIn, fraction: 1)
                return true
            }
            colored.isTemplate = false
            return colored
        }

        if !copy.isTemplate {
            return copy
        }

        copy.isTemplate = true
        return copy
    }

    private func rebuildMenu(
        settings: AppSettings,
        clipboardStatusTitle: String,
        isClipboardStatusActionEnabled: Bool,
        lastStatusMessage: String
    ) {
        menu.removeAllItems()

        addDisabledItem(OffsendStrings.appName)

        #if OFFSEND_INTERNAL
        addActionItem(OffsendStrings.menuStartOnboarding, action: #selector(openOnboardingItem))
        menu.addItem(.separator())
        #else
        if !settings.hasCompletedOnboarding {
            addActionItem(OffsendStrings.menuStartOnboarding, action: #selector(openOnboardingItem))
            menu.addItem(.separator())
        }
        #endif

        addActionItem(
            clipboardStatusTitle,
            action: #selector(showClipboardStatusItem),
            isEnabled: isClipboardStatusActionEnabled
        )
        menu.addItem(.separator())

        addActionItem(OffsendStrings.menuSafePaste, action: #selector(safePasteItem), keyEquivalent: "V", modifiers: [.command, .shift])
        addActionItem(OffsendStrings.menuRestorePlaceholders, action: #selector(restoreItem), keyEquivalent: "R", modifiers: [.command, .shift])
        menu.addItem(.separator())

        let protectionTitle = OffsendStrings.menuProtection(settings.protectionEnabled ? OffsendStrings.commonOn : OffsendStrings.commonOff)
        addActionItem(protectionTitle, action: #selector(toggleProtectionItem), state: settings.protectionEnabled ? .on : .off)

        let monitoringTitle = OffsendStrings.menuClipboardMonitoring(settings.clipboardMonitoringEnabled ? OffsendStrings.commonOn : OffsendStrings.commonOff)
        addActionItem(monitoringTitle, action: #selector(toggleClipboardMonitoringItem), state: settings.clipboardMonitoringEnabled ? .on : .off)
        menu.addItem(.separator())

        addActionItem(OffsendStrings.menuOpenSettings, action: #selector(openSettingsItem))
        addActionItem(OffsendStrings.menuCheckForUpdates, action: #selector(checkForUpdatesItem))
        menu.addItem(.separator())

        addDisabledItem(OffsendStrings.menuLastAction(lastStatusMessage))
        addActionItem(OffsendStrings.menuQuit, action: #selector(quitItem))
    }

    private func addDisabledItem(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addActionItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        state: NSControl.StateValue = .off,
        isEnabled: Bool = true
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.state = state
        item.isEnabled = isEnabled
        item.target = self
        menu.addItem(item)
    }

    @objc private func safePasteItem() {
        safePaste?()
    }

    @objc private func showClipboardStatusItem() {
        showClipboardStatus?()
    }

    @objc private func restoreItem() {
        restore?()
    }

    @objc private func toggleProtectionItem() {
        toggleProtection?()
    }

    @objc private func toggleClipboardMonitoringItem() {
        toggleClipboardMonitoring?()
    }

    @objc private func openOnboardingItem() {
        openOnboarding?()
    }

    @objc private func openSettingsItem() {
        openSettings?()
    }

    @objc private func checkForUpdatesItem() {
        checkForUpdates?()
    }

    @objc private func quitItem() {
        NSApplication.shared.terminate(nil)
    }
}

extension MenuBarStatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshBeforeOpen?()
    }
}
