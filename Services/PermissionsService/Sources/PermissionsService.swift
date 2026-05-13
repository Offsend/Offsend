import ApplicationServices
import AppKit
import Foundation

public protocol PermissionsServicing {
    var isAccessibilityTrusted: Bool { get }
    func requestAccessibilityPermission()
    func openAccessibilitySettings()
}

public final class PermissionsService: PermissionsServicing {
    public init() {}

    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
