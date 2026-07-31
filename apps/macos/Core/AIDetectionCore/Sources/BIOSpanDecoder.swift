import Foundation
import DetectionCore

public struct BIOSpan: Equatable, Sendable {
    public let label: String
    public let range: Range<String.Index>
    public let value: String
    /// Lowest per-token softmax probability across the span (worst-case confidence).
    public let confidence: Double

    public init(label: String, range: Range<String.Index>, value: String, confidence: Double = 1.0) {
        self.label = label
        self.range = range
        self.value = value
        self.confidence = confidence
    }
}

/// Decodes BIO/BIOES token labels into contiguous string spans.
public enum BIOSpanDecoder {
    /// Strips the BIO/BIOES prefix and returns the bare entity name, or `nil` for outside labels.
    public static func entityName(from label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "O", trimmed != "0" else { return nil }
        for prefix in ["B-", "I-", "B_", "I_", "E-", "S-"] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    public static func decode(
        text: String,
        tokenRanges: [Range<String.Index>],
        labels: [String],
        confidences: [Double] = []
    ) -> [BIOSpan] {
        guard tokenRanges.count == labels.count, !tokenRanges.isEmpty else { return [] }

        var spans: [BIOSpan] = []
        var currentLabel: String?
        var spanStart: String.Index?
        var spanEnd: String.Index?
        var spanConfidence = 1.0

        func flush() {
            guard let label = currentLabel, let start = spanStart, let end = spanEnd else { return }
            let range = start..<end
            guard !range.isEmpty else {
                currentLabel = nil
                spanStart = nil
                spanEnd = nil
                return
            }
            spans.append(BIOSpan(label: label, range: range, value: String(text[range]), confidence: spanConfidence))
            currentLabel = nil
            spanStart = nil
            spanEnd = nil
        }

        for (index, label) in labels.enumerated() {
            let tokenRange = tokenRanges[index]
            let tokenConfidence = index < confidences.count ? confidences[index] : 1.0
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let entityLabel = entityName(from: trimmed) else {
                flush()
                continue
            }

            // BIOES: `E-` continues and closes the current span, `S-` is a standalone single-token span.
            let isInside = trimmed.hasPrefix("I-") || trimmed.hasPrefix("I_") || trimmed.hasPrefix("E-")
            let closesSpan = trimmed.hasPrefix("E-") || trimmed.hasPrefix("S-")

            if isInside, currentLabel == entityLabel, spanStart != nil {
                spanEnd = tokenRange.upperBound
                spanConfidence = min(spanConfidence, tokenConfidence)
            } else {
                flush()
                currentLabel = entityLabel
                spanStart = tokenRange.lowerBound
                spanEnd = tokenRange.upperBound
                spanConfidence = tokenConfidence
            }

            if closesSpan {
                flush()
            }
        }

        flush()
        return spans
    }
}
