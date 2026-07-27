import Foundation

/// Recognizes editor-settings keys whose values a host process later executes:
/// interpreter and tool paths, terminal profiles, task commands.
///
/// Used for configuration that mixes ordinary preferences with execution
/// (`.vscode/settings.json`, `*.code-workspace`), where a blanket deny would
/// block routine agent edits. Content is inspected as JSON when it parses and
/// as raw text otherwise, because edit tools submit fragments rather than whole
/// files.
public enum ExecutableConfigContentInspector {
    /// Last dotted component of a settings key that names something executed.
    private static let executableKeySuffixes: Set<String> = [
        "path", "paths", "executable", "executablepath",
        "interpreter", "interpreterpath", "defaultinterpreterpath",
        "command", "commands", "runtimeexecutable", "shellpath",
        "server", "wrapper", "toolchain", "alternatetools",
        "prelaunchtask", "postdebugtask", "automationprofile",
    ]

    /// Key prefixes that are execution surfaces regardless of their leaf name.
    private static let executableKeyPrefixes: [String] = [
        "terminal.integrated.",
        "tasks",
        "launch",
    ]

    public static func introducesExecutableSetting(_ content: String) -> Bool {
        if let keys = jsonKeyPaths(in: content) {
            return keys.contains(where: isExecutableKey)
        }
        return rawTextMentionsExecutableKey(content)
    }

    /// True when `replaced` is text the file currently holds under an
    /// execution-sensitive key. An `Edit` that swaps only a value carries
    /// neither the key nor anything else recognizable in its payload, so the
    /// file on disk is what says which setting the edit lands on.
    public static func rewritesExecutableSetting(existing: String, replaced: String) -> Bool {
        let needle = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        guard let values = executableValues(in: existing) else {
            return executableKeyLines(in: existing).contains { $0.contains(needle) }
        }
        return values.contains { !$0.isEmpty && ($0.contains(needle) || needle.contains($0)) }
    }

    static func isExecutableKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        if executableKeyPrefixes.contains(where: normalized.hasPrefix) {
            return true
        }
        let leaf = normalized.split(separator: ".").last.map(String.init) ?? normalized
        return executableKeySuffixes.contains(leaf)
    }

    /// Dotted key paths in a JSON object/array, or `nil` when the text is not JSON.
    /// VS Code settings use flat dotted keys, but nested objects are also legal,
    /// so both forms have to collapse to the same key path.
    private static func jsonKeyPaths(in content: String) -> [String]? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(
                  with: data,
                  options: [.fragmentsAllowed]
              ) else {
            return nil
        }
        var keys: [String] = []
        collectKeyPaths(root, prefix: "", into: &keys)
        return keys
    }

    private static func collectKeyPaths(_ value: Any, prefix: String, into keys: inout [String]) {
        if let object = value as? [String: Any] {
            for (key, nested) in object {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                keys.append(path)
                collectKeyPaths(nested, prefix: path, into: &keys)
            }
            return
        }
        if let array = value as? [Any] {
            for element in array {
                collectKeyPaths(element, prefix: prefix, into: &keys)
            }
        }
    }

    /// String values reachable under an execution-sensitive key, or `nil` when
    /// the text is not JSON.
    private static func executableValues(in content: String) -> [String]? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(
                  with: data,
                  options: [.fragmentsAllowed]
              ) else {
            return nil
        }
        var values: [String] = []
        collectExecutableValues(root, prefix: "", into: &values)
        return values
    }

    private static func collectExecutableValues(_ value: Any, prefix: String, into values: inout [String]) {
        guard let object = value as? [String: Any] else { return }
        for (key, nested) in object {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if isExecutableKey(path) {
                collectStrings(nested, into: &values)
            } else {
                collectExecutableValues(nested, prefix: path, into: &values)
            }
        }
    }

    private static func collectStrings(_ value: Any, into values: inout [String]) {
        if let text = value as? String {
            values.append(text)
            return
        }
        if let object = value as? [String: Any] {
            for nested in object.values {
                collectStrings(nested, into: &values)
            }
            return
        }
        if let array = value as? [Any] {
            for element in array {
                collectStrings(element, into: &values)
            }
        }
    }

    /// Lines assigning an execution-sensitive key, for settings files that do
    /// not parse as JSON because they carry comments.
    private static func executableKeyLines(in content: String) -> [String] {
        content.split(separator: "\n").map(String.init).filter(rawTextMentionsExecutableKey)
    }

    /// Fallback for edit fragments and JSON with comments: look for a quoted key
    /// followed by a colon.
    private static func rawTextMentionsExecutableKey(_ content: String) -> Bool {
        let lower = content.lowercased()
        var searchRange = lower.startIndex..<lower.endIndex
        while let open = lower.range(of: "\"", range: searchRange) {
            let afterOpen = open.upperBound
            guard let close = lower.range(of: "\"", range: afterOpen..<lower.endIndex) else {
                return false
            }
            let key = String(lower[afterOpen..<close.lowerBound])
            let rest = lower[close.upperBound...].drop { $0 == " " || $0 == "\t" }
            if rest.first == ":", isExecutableKey(key) {
                return true
            }
            searchRange = close.upperBound..<lower.endIndex
        }
        return false
    }
}
