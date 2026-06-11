import AppKit
import SwiftUI

@MainActor
struct DocumentSanitizeWindowConfigurator: NSViewRepresentable, Equatable {
    let minimumSize: NSSize
    let preferredSize: NSSize
    let resetToken: UUID

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.minimumSize == rhs.minimumSize
            && lhs.preferredSize == rhs.preferredSize
            && lhs.resetToken == rhs.resetToken
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view, context: context)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard context.coordinator.lastConfiguration != self else { return }

        DispatchQueue.main.async {
            configureWindow(for: nsView, context: context)
        }
    }

    private func configureWindow(for view: NSView, context: Context) {
        guard let window = view.window else { return }

        window.setFrameAutosaveName("")
        window.minSize = minimumSize

        if context.coordinator.appliedResetToken != resetToken {
            window.setContentSize(preferredSize, animated: false)
            context.coordinator.appliedResetToken = resetToken
            context.coordinator.lastConfiguration = self
            return
        }

        let current = window.contentRect(forFrameRect: window.frame).size
        guard current.width < minimumSize.width || current.height < minimumSize.height else {
            context.coordinator.lastConfiguration = self
            return
        }

        window.setContentSize(
            NSSize(
                width: max(current.width, minimumSize.width),
                height: max(current.height, minimumSize.height)
            ),
            animated: false
        )
        context.coordinator.lastConfiguration = self
    }

    final class Coordinator {
        var appliedResetToken: UUID?
        var lastConfiguration: DocumentSanitizeWindowConfigurator?
    }
}

private extension NSWindow {
    func setContentSize(_ size: NSSize, animated: Bool) {
        guard animated else {
            setContentSize(size)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            setContentSize(size)
        }
    }
}
