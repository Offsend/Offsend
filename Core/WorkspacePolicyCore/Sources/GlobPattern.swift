import Foundation

/// A minimal glob matcher supporting only `*` (within a path segment), `**`
/// (across segments, including zero segments for `**/`) and `?` (a single
/// non-separator character). Character classes (`[...]`) and brace groups
/// (`{...}`) are treated as literals and are not expanded.
public struct GlobPattern: Equatable {
    private let regex: NSRegularExpression

    public init(_ pattern: String) {
        regex = GlobRegexCache.shared.regex(for: pattern)
    }

    public func matches(_ value: String) -> Bool {
        regex.firstMatch(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        ) != nil
    }

    fileprivate static func regexPattern(from glob: String) -> String {
        var regex = ""
        var index = glob.startIndex
        while index < glob.endIndex {
            let character = glob[index]
            if character == "*" {
                let nextIndex = glob.index(after: index)
                if nextIndex < glob.endIndex, glob[nextIndex] == "*" {
                    let afterDouble = glob.index(after: nextIndex)
                    if afterDouble < glob.endIndex, glob[afterDouble] == "/" {
                        // `**/` matches zero or more leading path segments, so a
                        // pattern like `**/*.mdc` also matches a root-level file.
                        regex += "(?:.*/)?"
                        index = glob.index(after: afterDouble)
                    } else {
                        regex += ".*"
                        index = afterDouble
                    }
                } else {
                    regex += #"[^/]*"#
                    index = nextIndex
                }
            } else if character == "?" {
                regex += #"[^/]"#
                index = glob.index(after: index)
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(character))
                index = glob.index(after: index)
            }
        }
        return regex
    }
}

/// Compiled glob regexes are immutable, so memoizing avoids recompiling the same
/// `NSRegularExpression` on every match during directory walks. Patterns include
/// user-authored ignore-file lines, so the cache is capped to bound memory in a
/// long-running app; on overflow it is cleared and entries recompile lazily.
private final class GlobRegexCache: @unchecked Sendable {
    static let shared = GlobRegexCache()

    /// Compiled from a fixed, always-valid literal; matches no input.
    private static let neverMatching = try! NSRegularExpression(pattern: "\\b\\B")
    private static let maximumEntries = 4096

    private let lock = NSLock()
    private var storage: [String: NSRegularExpression] = [:]

    func regex(for pattern: String) -> NSRegularExpression {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[pattern] {
            return cached
        }
        if storage.count >= Self.maximumEntries {
            storage.removeAll(keepingCapacity: true)
        }
        // The translation only emits escaped literals and standard glob tokens, so it
        // is always valid. The fallbacks keep an unexpected translation bug from
        // crashing the app: degrade to literal matching, then to "match nothing".
        let compiled = (try? NSRegularExpression(pattern: "^\(GlobPattern.regexPattern(from: pattern))$"))
            ?? (try? NSRegularExpression(pattern: "^\(NSRegularExpression.escapedPattern(for: pattern))$"))
            ?? Self.neverMatching
        storage[pattern] = compiled
        return compiled
    }
}
