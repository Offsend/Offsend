import AppKit
import Foundation

public protocol ClipboardServicing {
    func readString() -> String?
    func writeString(_ string: String)
    func temporarilyWrite(_ string: String, restoreAfter delay: TimeInterval, operation: @escaping () -> Void)
    func startMonitoring(interval: TimeInterval, onStringChange: @escaping (String) -> Void)
    func stopMonitoring()
}

public final class ClipboardService: ClipboardServicing {
    private let pasteboard: NSPasteboard
    private var monitorTimer: Timer?
    private var lastObservedChangeCount: Int
    private var lastObservedString: String?

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastObservedChangeCount = pasteboard.changeCount
        self.lastObservedString = pasteboard.string(forType: .string)
    }

    public func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    public func writeString(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        markCurrentPasteboardAsObserved()
    }

    public func temporarilyWrite(_ string: String, restoreAfter delay: TimeInterval = 0.8, operation: @escaping () -> Void) {
        let original = readString()
        writeString(string)
        operation()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let original else { return }
            self.writeString(original)
        }
    }

    public func startMonitoring(interval: TimeInterval = 0.6, onStringChange: @escaping (String) -> Void) {
        stopMonitoring()
        markCurrentPasteboardAsObserved()

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.publishChangeIfNeeded(onStringChange)
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    public func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func publishChangeIfNeeded(_ onStringChange: (String) -> Void) {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastObservedChangeCount else { return }

        lastObservedChangeCount = currentChangeCount
        guard let currentString = readString(), !currentString.isEmpty else {
            lastObservedString = nil
            return
        }

        guard currentString != lastObservedString else { return }

        lastObservedString = currentString
        onStringChange(currentString)
    }

    private func markCurrentPasteboardAsObserved() {
        lastObservedChangeCount = pasteboard.changeCount
        lastObservedString = readString()
    }
}
