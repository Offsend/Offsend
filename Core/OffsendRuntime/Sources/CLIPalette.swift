import Foundation

/// Wraps text in ANSI colors when enabled (interactive TTY only); otherwise passes text
/// through unchanged so piped/CI output stays plain. Shared by the CLI reporters.
public struct CLIPalette: Sendable {
    public let enabled: Bool

    public static let plain = CLIPalette(enabled: false)

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public func red(_ text: String) -> String { wrap(text, code: "31") }
    public func yellow(_ text: String) -> String { wrap(text, code: "33") }
    public func green(_ text: String) -> String { wrap(text, code: "32") }
    public func cyan(_ text: String) -> String { wrap(text, code: "36") }
    public func bold(_ text: String) -> String { wrap(text, code: "1") }
    public func dim(_ text: String) -> String { wrap(text, code: "2") }

    private func wrap(_ text: String, code: String) -> String {
        guard enabled, !text.isEmpty else { return text }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }
}
