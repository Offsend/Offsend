import AppKit
import SwiftUI

extension View {
    /// Makes the red close button close the window instead of hiding it.
    func dismissOnWindowCloseButton(
        onWillClose: (@MainActor () -> Void)? = nil
    ) -> some View {
        background(WindowCloseDismissConfigurator(onWillClose: onWillClose))
    }

    /// Invokes `action` when the hosting `NSWindow` is about to close.
    func onWindowWillClose(perform action: @escaping @MainActor () -> Void) -> some View {
        background(WindowWillCloseObserver(action: action))
    }
}

@MainActor
private struct WindowWillCloseObserver: NSViewRepresentable {
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: @unchecked Sendable {
        private let action: @MainActor () -> Void
        private weak var observedWindow: NSWindow?
        private var observer: NSObjectProtocol?

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        func attach(to view: NSView) {
            guard let window = view.window else { return }
            guard window !== observedWindow else { return }
            detach()

            observedWindow = window
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.action()
                }
            }
        }

        @MainActor
        func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            observedWindow = nil
        }

        @MainActor
        deinit {
            detach()
        }
    }
}

@MainActor
private struct WindowCloseDismissConfigurator: NSViewRepresentable {
    let onWillClose: (@MainActor () -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onWillClose: onWillClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private let onWillClose: (@MainActor () -> Void)?
        private weak var attachedWindow: NSWindow?

        init(onWillClose: (@MainActor () -> Void)?) {
            self.onWillClose = onWillClose
        }

        deinit {
            guard let window = attachedWindow else { return }

            let coordinatorID = ObjectIdentifier(self)

            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    Self.cleanup(window: window, coordinatorID: coordinatorID)
                }
            } else {
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        Self.cleanup(window: window, coordinatorID: coordinatorID)
                    }
                }
            }
        }

        @MainActor
        private static func cleanup(window: NSWindow, coordinatorID: ObjectIdentifier) {
            if let delegate = window.delegate,
               ObjectIdentifier(delegate as AnyObject) == coordinatorID {
                window.delegate = nil
            }

            if let closeButton = window.standardWindowButton(.closeButton),
               let target = closeButton.target,
               ObjectIdentifier(target as AnyObject) == coordinatorID {
                closeButton.target = nil
                closeButton.action = nil
            }
        }

        @MainActor
        func attach(to view: NSView) {
            guard let window = view.window else { return }

            attachedWindow = window
            window.isReleasedWhenClosed = true

            if window.delegate !== self {
                window.delegate = self
            }

            guard let closeButton = window.standardWindowButton(.closeButton) else { return }
            if closeButton.target !== self || closeButton.action != #selector(closeWindow(_:)) {
                closeButton.target = self
                closeButton.action = #selector(closeWindow(_:))
            }
        }

        @MainActor
        @objc private func closeWindow(_ sender: Any?) {
            attachedWindow?.close()
        }

        @MainActor
        @objc func windowWillClose(_ notification: Notification) {
            onWillClose?()
        }

        @MainActor
        @objc func windowShouldClose(_ sender: NSWindow) -> Bool {
            onWillClose?()
            return true
        }
    }
}
