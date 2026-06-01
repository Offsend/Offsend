import ApplicationServices
import AppKit
import Combine
import Foundation

@MainActor
public protocol PermissionsServicing: AnyObject {
    var isAccessibilityTrusted: Bool { get }
    func requestAccessibilityPermission()
    func openAccessibilitySettings()
    func startMonitoring()
    func stopMonitoring()
}

@MainActor
public final class PermissionsService: ObservableObject, PermissionsServicing {
    @Published public private(set) var isAccessibilityTrusted: Bool

    private var activationObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var monitoringConsumerCount = 0

    public init() {
        isAccessibilityTrusted = Self.queryAccessibilityTrusted()
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        pollTimer?.invalidate()
    }

    public func startMonitoring() {
        monitoringConsumerCount += 1
        guard monitoringConsumerCount == 1 else { return }

        refreshTrustStatus()

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTrustStatus()
            }
        }

        updatePollingTimer()
    }

    public func stopMonitoring() {
        guard monitoringConsumerCount > 0 else { return }
        monitoringConsumerCount -= 1
        guard monitoringConsumerCount == 0 else { return }

        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refreshTrustStatus()
    }

    public func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func refreshTrustStatus() {
        let trusted = Self.queryAccessibilityTrusted()
        if isAccessibilityTrusted != trusted {
            isAccessibilityTrusted = trusted
        }
        updatePollingTimer()
    }

    private func updatePollingTimer() {
        if isAccessibilityTrusted {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }

        guard pollTimer == nil else { return }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTrustStatus()
            }
        }
    }

    private static func queryAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }
}
