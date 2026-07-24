import Foundation
import MaskingCore

public struct OffsendMCPJSONFieldTransformResult: Equatable, Sendable {
    public let text: String
    public let sealedCount: Int
    public let droppedCount: Int

    public var transformedCount: Int { sealedCount + droppedCount }

    public init(text: String, sealedCount: Int, droppedCount: Int) {
        self.text = text
        self.sealedCount = sealedCount
        self.droppedCount = droppedCount
    }
}

public enum OffsendMCPJSONFieldTransformError: Error, Equatable, Sendable {
    case invalidJSON
    case sealRequired
    case sealFailed
}

/// Subtractive JSON field policy for MCP responses (`context.mcp.rules[].fields`).
///
/// - `seal` / `drop` / `pass` only; never renames or retypes keys.
/// - Bare key names (no `.` / `*`) match that key at any depth.
/// - Dotted paths support `*` (one segment) and `**` (zero or more segments).
public enum OffsendMCPJSONFieldTransformer {
    public static let sealType = "FIELD"

    public static func apply(
        jsonText: String,
        fields: [String: OffsendMCPFieldAction],
        sealPlaintext: ((String) throws -> String)?
    ) throws -> OffsendMCPJSONFieldTransformResult {
        guard !fields.isEmpty else {
            return OffsendMCPJSONFieldTransformResult(text: jsonText, sealedCount: 0, droppedCount: 0)
        }
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              root is [String: Any] || root is [Any] else {
            throw OffsendMCPJSONFieldTransformError.invalidJSON
        }

        let needsSeal = fields.values.contains(.seal)
        if needsSeal, sealPlaintext == nil {
            throw OffsendMCPJSONFieldTransformError.sealRequired
        }

        var sealedCount = 0
        var droppedCount = 0
        let transformed: Any
        do {
            transformed = try transform(
                root,
                path: [],
                inherited: nil,
                fields: fields,
                sealPlaintext: sealPlaintext,
                sealedCount: &sealedCount,
                droppedCount: &droppedCount
            )
        } catch {
            throw OffsendMCPJSONFieldTransformError.sealFailed
        }

        guard JSONSerialization.isValidJSONObject(transformed),
              let outData = try? JSONSerialization.data(
                withJSONObject: transformed,
                options: [.sortedKeys]
              ),
              let outText = String(data: outData, encoding: .utf8) else {
            throw OffsendMCPJSONFieldTransformError.invalidJSON
        }
        return OffsendMCPJSONFieldTransformResult(
            text: outText,
            sealedCount: sealedCount,
            droppedCount: droppedCount
        )
    }

    // MARK: - Walk

    private static func transform(
        _ value: Any,
        path: [String],
        inherited: OffsendMCPFieldAction?,
        fields: [String: OffsendMCPFieldAction],
        sealPlaintext: ((String) throws -> String)?,
        sealedCount: inout Int,
        droppedCount: inout Int
    ) throws -> Any {
        let action = bestAction(for: path, fields: fields) ?? inherited

        if action == .drop {
            droppedCount += 1
            return NSNull()
        }

        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for key in dict.keys.sorted() {
                guard let child = dict[key] else { continue }
                let childPath = path + [key]
                out[key] = try transform(
                    child,
                    path: childPath,
                    inherited: action == .seal ? .seal : nil,
                    fields: fields,
                    sealPlaintext: sealPlaintext,
                    sealedCount: &sealedCount,
                    droppedCount: &droppedCount
                )
            }
            return out
        }

        if let array = value as? [Any] {
            return try array.enumerated().map { index, child in
                try transform(
                    child,
                    path: path + ["\(index)"],
                    inherited: action == .seal ? .seal : nil,
                    fields: fields,
                    sealPlaintext: sealPlaintext,
                    sealedCount: &sealedCount,
                    droppedCount: &droppedCount
                )
            }
        }

        if action == .seal {
            return try sealScalar(
                value,
                sealPlaintext: sealPlaintext,
                sealedCount: &sealedCount
            )
        }

        return value
    }

    private static func sealScalar(
        _ value: Any,
        sealPlaintext: ((String) throws -> String)?,
        sealedCount: inout Int
    ) throws -> Any {
        guard let sealPlaintext else {
            throw OffsendMCPJSONFieldTransformError.sealRequired
        }
        if value is NSNull { return value }

        let plaintext: String?
        if let string = value as? String {
            plaintext = string.isEmpty ? nil : string
        } else if let bool = value as? Bool {
            plaintext = bool ? "true" : "false"
        } else if let int = value as? Int {
            plaintext = String(int)
        } else if let double = value as? Double {
            plaintext = String(double)
        } else if let number = value as? NSNumber {
            plaintext = number.stringValue
        } else {
            plaintext = nil
        }

        guard let plaintext else { return value }
        let token = try sealPlaintext(plaintext)
        sealedCount += 1
        return token
    }

    // MARK: - Path match

    static func bestAction(
        for path: [String],
        fields: [String: OffsendMCPFieldAction]
    ) -> OffsendMCPFieldAction? {
        guard !path.isEmpty else { return nil }
        var best: (action: OffsendMCPFieldAction, score: Int)?
        for (pattern, action) in fields {
            guard matches(pattern: pattern, path: path) else { continue }
            let score = specificity(pattern)
            if let current = best {
                if score > current.score
                    || (score == current.score && actionRank(action) > actionRank(current.action)) {
                    best = (action, score)
                }
            } else {
                best = (action, score)
            }
        }
        return best?.action
    }

    /// Bare key → last-segment match at any depth. Otherwise dotted glob with `*` / `**`.
    static func matches(pattern: String, path: [String]) -> Bool {
        if pattern.contains(".") || pattern.contains("*") {
            return matchGlob(patternParts: splitPattern(pattern), path: path)
        }
        return path.last == pattern
    }

    static func specificity(_ pattern: String) -> Int {
        if !pattern.contains("."), !pattern.contains("*") {
            // Any-depth bare key: weaker than an explicit dotted path of same leaf.
            return 2
        }
        let parts = splitPattern(pattern)
        var score = parts.count * 2
        for part in parts {
            if part == "**" {
                score += 0
            } else if part == "*" || part.contains("*") {
                score += 1
            } else {
                score += 3
            }
        }
        return score
    }

    private static func actionRank(_ action: OffsendMCPFieldAction) -> Int {
        switch action {
        case .pass: return 0
        case .drop: return 1
        case .seal: return 2
        }
    }

    private static func splitPattern(_ pattern: String) -> [String] {
        pattern.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }

    private static func matchGlob(patternParts: [String], path: [String]) -> Bool {
        matchGlob(patternParts, path, pi: 0, si: 0)
    }

    private static func matchGlob(
        _ pattern: [String],
        _ path: [String],
        pi: Int,
        si: Int
    ) -> Bool {
        if pi == pattern.count {
            return si == path.count
        }
        let part = pattern[pi]
        if part == "**" {
            if pi == pattern.count - 1 { return true }
            var next = si
            while next <= path.count {
                if matchGlob(pattern, path, pi: pi + 1, si: next) {
                    return true
                }
                next += 1
            }
            return false
        }
        guard si < path.count else { return false }
        guard matchSegment(part, path[si]) else { return false }
        return matchGlob(pattern, path, pi: pi + 1, si: si + 1)
    }

    /// Case-sensitive segment match (`*` = any run of characters).
    private static func matchSegment(_ pattern: String, _ value: String) -> Bool {
        if pattern == "*" { return true }
        if !pattern.contains("*") { return pattern == value }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        guard let regex = try? NSRegularExpression(pattern: "^\(escaped)$") else {
            return pattern == value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}
