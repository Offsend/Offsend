import Foundation

/// Reconstructs adjacent static string concatenations in interpreter payloads
/// (`python -c`, `node -e`) so path heuristics see `"cert.pem"` instead of
/// `"c"+"ert"+".pem"`.
///
/// Scope is intentionally narrow: only `+` between plain `'…'` / `"…"` literals.
/// f-strings, raw/byte prefixes, template literals, and non-literal operands
/// are left alone.
public enum InterpreterScriptPathNormalizer {
    /// Joins every static `"a"+"b"` / `'a'+'b'` chain in `source` (including
    /// chains of three or more) until a fixed point.
    public static func joiningAdjacentStringLiterals(_ source: String) -> String {
        var current = source
        // Cap passes so a pathological input cannot loop.
        for _ in 0..<32 {
            let next = joinPass(current)
            if next == current { return current }
            current = next
        }
        return current
    }

    private static func joinPass(_ source: String) -> String {
        let characters = Array(source)
        var output = ""
        var index = 0
        while index < characters.count {
            if let joined = joinChain(startingAt: index, in: characters) {
                output += joined.text
                index = joined.end
            } else {
                output.append(characters[index])
                index += 1
            }
        }
        return output
    }

    private struct JoinedChain {
        let text: String
        let end: Int
    }

    /// At `start`, parse one or more plain string literals joined by `+`.
    /// Returns nil when fewer than two literals participate.
    private static func joinChain(startingAt start: Int, in characters: [Character]) -> JoinedChain? {
        guard let first = parsePlainStringLiteral(at: start, in: characters) else {
            return nil
        }
        var content = first.content
        var cursor = first.end
        var joinedCount = 1

        while true {
            let afterSpace = skipWhitespace(from: cursor, in: characters)
            guard afterSpace < characters.count, characters[afterSpace] == "+" else {
                break
            }
            let afterPlus = skipWhitespace(from: afterSpace + 1, in: characters)
            guard let next = parsePlainStringLiteral(at: afterPlus, in: characters) else {
                break
            }
            content += next.content
            cursor = next.end
            joinedCount += 1
        }

        guard joinedCount >= 2 else { return nil }
        let quote = first.quote
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: String(quote), with: "\\\(quote)")
        return JoinedChain(text: "\(quote)\(escaped)\(quote)", end: cursor)
    }

    private struct ParsedLiteral {
        let quote: Character
        let content: String
        let end: Int
    }

    /// Plain `'…'` / `"…"`. Rejects f/r/b/u-prefixed strings and backticks.
    private static func parsePlainStringLiteral(
        at start: Int,
        in characters: [Character]
    ) -> ParsedLiteral? {
        guard start < characters.count else { return nil }
        let quote = characters[start]
        guard quote == "'" || quote == "\"" else { return nil }
        if start > 0 {
            let previous = characters[start - 1]
            if previous.isLetter || previous == "_" {
                // f"…", r'…', b"…", identifiers abutting a quote.
                return nil
            }
        }

        var index = start + 1
        var content = ""
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                guard index + 1 < characters.count else { return nil }
                content.append(characters[index + 1])
                index += 2
                continue
            }
            if character == quote {
                return ParsedLiteral(quote: quote, content: content, end: index + 1)
            }
            content.append(character)
            index += 1
        }
        return nil
    }

    private static func skipWhitespace(from start: Int, in characters: [Character]) -> Int {
        var index = start
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
        return index
    }
}
