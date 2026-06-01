import AppKit
import SwiftUI

@MainActor
final class DockIconVisibilityService: NSObject, ObservableObject {
    private let trackedWindows = NSHashTable<NSWindow>.weakObjects()

    /// Call before `openWindow` when presenting from the menu bar or other accessory UI.
    func prepareForWindowPresentation() {
        showDockIcon()
    }

    func track(_ window: NSWindow) {
        guard window.isVisible || window.isMiniaturized else { return }

        let isNew = !trackedWindows.contains(window)
        if isNew {
            trackedWindows.add(window)
            registerObservers(for: window)
            presentWindow(window)
            schedulePresentationRetry(for: window)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func registerObservers(for window: NSWindow) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeOcclusionState(_:)),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    private func unregisterObservers(for window: NSWindow) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: window
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeMainNotification,
            object: window
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        untrack(window)
    }

    @objc private func windowDidChangeOcclusionState(_ notification: Notification) {
        reconcileTrackedWindows()
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.reconcileTrackedWindows()
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              trackedWindows.contains(window),
              window.isVisible || window.isMiniaturized else {
            return
        }

        showDockIcon()
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              trackedWindows.contains(window),
              window.isVisible || window.isMiniaturized else {
            return
        }

        presentWindow(window)
    }

    private func untrack(_ window: NSWindow) {
        unregisterObservers(for: window)
        trackedWindows.remove(window)
        updateDockIconVisibility()
    }

    private func reconcileTrackedWindows() {
        let hiddenWindows = trackedWindows.allObjects.filter { !$0.isVisible && !$0.isMiniaturized }
        guard !hiddenWindows.isEmpty else { return }

        for window in hiddenWindows {
            unregisterObservers(for: window)
            trackedWindows.remove(window)
        }
        updateDockIconVisibility()
    }

    private func updateDockIconVisibility() {
        if trackedWindows.allObjects.isEmpty {
            hideDockIcon()
        } else {
            showDockIcon()
        }
    }

    private func showDockIcon() {
        if NSApp.activationPolicy() != .regular {
            _ = NSApp.setActivationPolicy(.regular)
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideDockIcon() {
        guard NSApp.activationPolicy() != .accessory else { return }
        _ = NSApp.setActivationPolicy(.accessory)
    }

    private func presentWindow(_ window: NSWindow) {
        guard window.isVisible || window.isMiniaturized else { return }

        showDockIcon()

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func schedulePresentationRetry(for window: NSWindow) {
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            guard self.trackedWindows.contains(window) else { return }
            guard window.isVisible || window.isMiniaturized else {
                self.reconcileTrackedWindows()
                return
            }
            self.presentWindow(window)
        }
    }
}

extension View {
    func tracksDockIconWindow(using service: DockIconVisibilityService) -> some View {
        background(DockIconWindowReader(service: service))
    }
}

private struct DockIconWindowReader: NSViewRepresentable {
    let service: DockIconVisibilityService

    func makeNSView(context: Context) -> DockIconTrackingView {
        let view = DockIconTrackingView()
        view.service = service
        return view
    }

    func updateNSView(_ nsView: DockIconTrackingView, context: Context) {
        nsView.service = service
        nsView.trackCurrentWindow()
    }
}

private final class DockIconTrackingView: NSView {
    weak var service: DockIconVisibilityService?
    private var visibilityObserver: NSObjectProtocol?

    deinit {
        if let visibilityObserver {
            NotificationCenter.default.removeObserver(visibilityObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let visibilityObserver {
            NotificationCenter.default.removeObserver(visibilityObserver)
            self.visibilityObserver = nil
        }

        if let window {
            visibilityObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.trackCurrentWindow()
            }
        }

        trackCurrentWindow()
    }

    func trackCurrentWindow() {
        guard let window else { return }
        service?.track(window)
    }
}
