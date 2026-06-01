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

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var attachedWindow: NSWindow?

        nonisolated deinit {
            MainActor.assumeIsolated {
                cleanup()
            }
        }

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

        @objc private func closeWindow(_ sender: Any?) {
            attachedWindow?.close()
        }

        @objc func windowShouldClose(_ sender: NSWindow) -> Bool {
            true
        }

        private func cleanup() {
            guard let window = attachedWindow else { return }

            if window.delegate === self {
                window.delegate = nil
            }

            if let closeButton = window.standardWindowButton(.closeButton),
               closeButton.target === self {
                closeButton.target = nil
                closeButton.action = nil
            }
        }
    }
}
