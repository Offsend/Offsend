import Foundation

/// Shared text layout for CLI reporters and interactive commands.
/// Keeps TTY output consistent (sections, markers, next-steps) without changing JSON payloads.
public struct CLIText: Sendable {
    public let palette: CLIPalette

    public init(useColor: Bool) {
        palette = CLIPalette(enabled: useColor)
    }

    public init(palette: CLIPalette) {
        self.palette = palette
    }

    // MARK: Markers

    public func ok(_ text: String) -> String {
        palette.green("✓ \(text)")
    }

    public func warn(_ text: String) -> String {
        palette.yellow("! \(text)")
    }

    public func fail(_ text: String) -> String {
        palette.red("✗ \(text)")
    }

    public func info(_ text: String) -> String {
        palette.cyan("• \(text)")
    }

    // MARK: Structure

    public func title(_ text: String) -> String {
        palette.bold(text)
    }

    public func section(_ name: String) -> String {
        palette.bold(name)
    }

    public func add(_ path: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "  + \(path)  \(palette.dim(detail))"
        }
        return "  + \(path)"
    }

    public func update(_ path: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "  ~ \(path)  \(palette.dim(detail))"
        }
        return "  ~ \(path)"
    }

    public func item(_ path: String, detail: String? = nil) -> String {
        if let detail, !detail.isEmpty {
            return "  - \(path)  \(palette.dim(detail))"
        }
        return "  - \(path)"
    }

    public func hint(_ text: String) -> String {
        palette.dim(text)
    }

    /// Two-space indented dim line for section bodies, so hierarchy survives
    /// without ANSI (NO_COLOR, pipes, CI logs).
    public func note(_ text: String) -> String {
        "  \(palette.dim(text))"
    }

    public func next(_ command: String) -> String {
        palette.cyan("→ Next: \(command)")
    }

    public func step(current: Int, total: Int, title: String) -> String {
        let prefix = palette.cyan("Step \(current)/\(total)")
        return "\(prefix) — \(palette.bold(title))"
    }

    /// Join lines, preserving intentional blank separators already present in the array.
    public static func join(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    public static func joinSections(_ sections: [[String]]) -> String {
        sections
            .map { $0.filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
            .map { $0.joined(separator: "\n") }
            .joined(separator: "\n\n")
    }
}
