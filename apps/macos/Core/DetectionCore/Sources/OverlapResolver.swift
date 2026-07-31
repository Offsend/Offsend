import Foundation

public protocol SensitiveDataDetecting: Sendable {
    func scan(_ request: DetectionRequest) async -> DetectionResult
}

/// Merges overlapping entity spans, keeping the higher-priority match's metadata.
public enum OverlapResolver {
    public static func resolve(_ entities: [SensitiveEntity], in text: String) -> [SensitiveEntity] {
        let sorted = entities.sorted { lhs, rhs in
            if lhs.range.lowerBound == rhs.range.lowerBound {
                return priority(lhs) > priority(rhs)
            }
            return lhs.range.lowerBound < rhs.range.lowerBound
        }

        // Entities are sorted by `lowerBound`, so a new entity can only overlap the most recent
        // kept one. Overlapping spans are merged into a single covering entity so no flagged
        // character is left unmasked; metadata follows the higher-priority match.
        return sorted.reduce(into: [SensitiveEntity]()) { result, entity in
            guard let last = result.last, last.range.overlaps(entity.range) else {
                result.append(entity)
                return
            }
            result[result.count - 1] = merge(last, entity, in: text)
        }
    }

    private static func merge(_ lhs: SensitiveEntity, _ rhs: SensitiveEntity, in text: String) -> SensitiveEntity {
        let winner = priority(rhs) > priority(lhs) ? rhs : lhs
        let lowerBound = min(lhs.range.lowerBound, rhs.range.lowerBound)
        let upperBound = max(lhs.range.upperBound, rhs.range.upperBound)
        let range = lowerBound..<upperBound
        return SensitiveEntity(
            id: winner.id,
            type: winner.type,
            range: range,
            value: String(text[range]),
            confidence: winner.confidence,
            source: winner.source
        )
    }

    private static func priority(_ entity: SensitiveEntity) -> Int {
        // Fuzzy length/heuristic: must not suppress a concrete `https?://…` URL match on overlap.
        if entity.type == .highEntropyString { return 95 }
        if entity.type.isSecret { return 1_000 }
        // Loose `phone` regex overlaps spaced digit groups; prefer PAN detection when both match.
        if entity.type == .creditCardLike { return 120 }
        // Prefer full IPv4 over partial phone matches (`104.16.175` + trailing `.22`).
        if entity.type == .ipAddress { return 115 }
        if entity.type == .phone { return 85 }
        switch entity.source {
        case .customDictionary:
            return 500
        case .ai:
            return 90
        case .regex:
            return 100
        case .secret:
            return 1_000
        }
    }
}
