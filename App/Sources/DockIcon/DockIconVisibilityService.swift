import AppKit
import SwiftUI

@MainActor
final class DockIconVisibilityService: NSObject, ObservableObject {
    private let trackedWindows = NSHashTable<NSWindow>.weakObjects()

    func track(_ window: NSWindow) {
        guard !trackedWindows.contains(window) else { return }

        trackedWindows.add(window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )

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
        trackedWindows.remove(window)
        updateDockIconVisibility()
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        trackCurrentWindow()
    }

    func trackCurrentWindow() {
        guard let window else { return }

        service?.track(window)
    }
}
