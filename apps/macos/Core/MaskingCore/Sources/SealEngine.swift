import DetectionCore
import Foundation

public struct SealResult: Equatable, Sendable {
    public let sealedText: String
    public let sealedCount: Int

    public init(sealedText: String, sealedCount: Int) {
        self.sealedText = sealedText
        self.sealedCount = sealedCount
    }
}

/// Parallel to `TextMasking` — lets App / DocumentCore inject sealing without depending on CLI.
public protocol TextSealing: Sendable {
    func seal(text: String, entities: [SensitiveEntity]) throws -> SealResult
    func unseal(text: String) throws -> String
}

/// Detects embed seal tokens without a key (for restore routing in the app).
public enum SealTokenDetector: Sendable {
    public static let pattern: NSRegularExpression = try! NSRegularExpression(
        pattern: #"\{\{([A-Z][A-Z0-9_]*):v1\.([A-Za-z0-9_-]+)\}\}"#
    )

    public static func containsSealTokens(in text: String) -> Bool {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return pattern.firstMatch(in: text, options: [], range: nsRange) != nil
    }

    public static func tokenCount(in text: String) -> Int {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return pattern.numberOfMatches(in: text, options: [], range: nsRange)
    }

    public static func tokenRanges(in text: String) -> [Range<String.Index>] {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return pattern.matches(in: text, options: [], range: nsRange)
            .compactMap { Range($0.range, in: text) }
    }

    /// Inner `TYPE:v1.<payload>` shape (without braces). `apiKeyGeneric`'s
    /// `secret\s*[:=]\s*…` pattern matches `SECRET:v1.…` framing.
    private static let innerStructurePattern: NSRegularExpression = try! NSRegularExpression(
        pattern: #"^[A-Z][A-Z0-9_]*:v1\.[A-Za-z0-9_-]+$"#,
        options: [.caseInsensitive]
    )

    /// Drops findings fully contained in a seal token, except concrete secret
    /// detectors whose value is *not* the seal framing itself. Ciphertext
    /// commonly false-triggers phone / high-entropy / `apiKeyGeneric` on
    /// `SECRET:v1.…`; a live key wrapped in a fake `{{TYPE:v1.…}}` still fires.
    public static func excludingTokenSpans(
        _ entities: [SensitiveEntity],
        in text: String
    ) -> [SensitiveEntity] {
        guard !entities.isEmpty, containsSealTokens(in: text) else { return entities }
        let tokenSpans = tokenRanges(in: text)
        return entities.filter { entity in
            let inside = tokenSpans.contains {
                entity.range.lowerBound >= $0.lowerBound && entity.range.upperBound <= $0.upperBound
            }
            guard inside else { return true }
            return entity.type.countsAsCriticalSecret && !isSealTokenStructure(entity.value)
        }
    }

    private static func isSealTokenStructure(_ value: String) -> Bool {
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        return innerStructurePattern.firstMatch(in: value, options: [], range: nsRange) != nil
    }
}
