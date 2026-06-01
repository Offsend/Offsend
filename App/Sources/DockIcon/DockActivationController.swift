import AppKit

/// Keeps the Dock icon in sync with user-facing windows for a menu bar (accessory) app.
@MainActor
final class DockActivationController: NSObject {
    private var policyUpdateWorkItem: DispatchWorkItem?
    private var presentationFallbackWorkItem: DispatchWorkItem?
    private var isObserving = false

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.willCloseNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSApplication.didBecomeActiveNotification,
        ]
        for name in names {
            center.addObserver(
                self,
                selector: #selector(windowLifecycleDidChange(_:)),
                name: name,
                object: nil
            )
        }

        updateActivationPolicy()
    }

    /// Call before `openWindow` when presenting from the menu bar or other accessory UI.
    func prepareForWindowPresentation() {
        showInDock(activate: true)
        schedulePresentationFallbackCheck()
    }

    func handleApplicationReopen(hasVisibleWindows: Bool) {
        if hasVisibleWindows {
            frontPresentableWindows(activate: true)
        } else {
            prepareForWindowPresentation()
        }
        scheduleActivationPolicyUpdate()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowLifecycleDidChange(_ notification: Notification) {
        scheduleActivationPolicyUpdate()
    }

    private func scheduleActivationPolicyUpdate() {
        policyUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateActivationPolicy()
        }
        policyUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func schedulePresentationFallbackCheck() {
        presentationFallbackWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateActivationPolicy()
        }
        presentationFallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func updateActivationPolicy() {
        if hasPresentableWindows {
            showInDock(activate: false)
        } else {
            hideFromDock()
        }
    }

    private var hasPresentableWindows: Bool {
        NSApp.windows.contains { Self.isPresentableUserWindow($0) }
    }

    static func isPresentableUserWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible || window.isMiniaturized else { return false }
        guard !window.isSheet else { return false }
        guard window.level == .normal || window.level == .floating else { return false }

        if window.isMiniaturized {
            return window.canBecomeMain || window.canBecomeKey
        }

        guard window.canBecomeKey || window.canBecomeMain else { return false }

        let size = window.frame.size
        guard size.width > 1, size.height > 1 else { return false }

        return true
    }

    private func showInDock(activate: Bool) {
        if NSApp.activationPolicy() != .regular {
            guard NSApp.setActivationPolicy(.regular) else { return }
        }
        NSApp.unhide(nil)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func hideFromDock() {
        guard NSApp.activationPolicy() != .accessory else { return }
        _ = NSApp.setActivationPolicy(.accessory)
    }

    func frontPresentableWindows(activate: Bool) {
        showInDock(activate: activate)

        for window in NSApp.windows where Self.isPresentableUserWindow(window) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
