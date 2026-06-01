import AppKit
import SwiftUI

extension View {
    /// Makes the red close button close the window instead of hiding it.
    func dismissOnWindowCloseButton() -> some View {
        background(WindowCloseDismissConfigurator())
    }
}

@MainActor
private struct WindowCloseDismissConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
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
        private weak var attachedWindow: NSWindow?

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
        @objc func windowShouldClose(_ sender: NSWindow) -> Bool {
            true
        }
    }
}
