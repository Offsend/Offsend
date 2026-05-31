import AppKit
import SwiftUI

@MainActor
final class DockIconVisibilityService: NSObject, ObservableObject {
    private let trackedWindows = NSHashTable<NSWindow>.weakObjects()

    func track(_ window: NSWindow) {
        if !trackedWindows.contains(window) {
            trackedWindows.add(window)
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
        }

        showDockIcon()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

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
        trackedWindows.remove(window)
        updateDockIconVisibility()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              trackedWindows.contains(window) else {
            return
        }

        showDockIcon()
    }

    private func updateDockIconVisibility() {
        if trackedWindows.allObjects.isEmpty {
            _ = NSApp.setActivationPolicy(.accessory)
        } else {
            showDockIcon()
        }
    }

    private func showDockIcon() {
        _ = NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
    private var keyObserver: NSObjectProtocol?

    deinit {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let observer = keyObserver {
            NotificationCenter.default.removeObserver(observer)
            keyObserver = nil
        }

        if let window {
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.trackCurrentWindow()
            }
        }

        trackCurrentWindow()
    }

    func trackCurrentWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.service?.track(window)
        }
    }
}
