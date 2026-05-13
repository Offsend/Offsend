import ApplicationServices
import AppKit
import Foundation

public protocol PasteServicing {
    var canPasteIntoActiveApp: Bool { get }
    func pasteIntoActiveApp()
}

public final class PasteService: PasteServicing {
    public init() {}

    public var canPasteIntoActiveApp: Bool {
        AXIsProcessTrusted()
    }

    public func pasteIntoActiveApp() {
        guard canPasteIntoActiveApp else { return }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
