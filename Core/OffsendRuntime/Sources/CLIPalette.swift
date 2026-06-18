import Foundation

/// Wraps text in ANSI colors when enabled (interactive TTY only); otherwise passes text
/// through unchanged so piped/CI output stays plain. Shared by the CLI reporters.
struct CLIPalette: Sendable {
    let enabled: Bool

    static let plain = CLIPalette(enabled: false)

    func red(_ text: String) -> String { wrap(text, code: "31") }
    func yellow(_ text: String) -> String { wrap(text, code: "33") }
    func green(_ text: String) -> String { wrap(text, code: "32") }
    func dim(_ text: String) -> String { wrap(text, code: "2") }

    private func wrap(_ text: String, code: String) -> String {
        guard enabled, !text.isEmpty else { return text }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }
}
