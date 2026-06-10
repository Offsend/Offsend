import Foundation

enum LLMPIIExtractor {
    private static let maxChunkLength = 4_000

    static func buildPrompt(for text: String) -> String {
        """
        Extract personally identifiable or sensitive entities from the user text.
        Return ONLY valid JSON with this shape:
        {"entities":[{"type":"PERSON","text":"exact substring"}, ...]}
        Allowed type values: PERSON, EMAIL, PHONE, ADDRESS, ORGANIZATION, GOVERNMENT_ID, CREDIT_CARD, SENSITIVE_TERM.
        Use exact substrings from the input. If none, return {"entities":[]}.
        Do not include markdown or commentary.

        TEXT:
        \(text)
        """
    }

    static func parseEntities(
        jsonText: String,
        in sourceText: String,
        options: DetectionOptions
    ) -> [SensitiveEntity] {
        guard let data = extractJSONData(from: jsonText) else { return [] }
        struct Payload: Decodable {
            struct Item: Decodable {
                let type: String
                let text: String
            }
            let entities: [Item]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }

        var usedRanges: [Range<String.Index>] = []
        var entities: [SensitiveEntity] = []

        for item in payload.entities {
            let value = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard let entityType = mapType(item.type) else { continue }
            guard options.enabledTypes.contains(entityType) else { continue }
            guard let range = firstRange(of: value, in: sourceText, excluding: usedRanges) else { continue }
            usedRanges.append(range)
            entities.append(
                SensitiveEntity(
                    type: entityType,
                    range: range,
                    value: String(sourceText[range]),
                    confidence: 0.7,
                    source: .ai
                )
            )
        }
        return entities
    }

    struct Chunk: Sendable {
        let substring: String
        let base: String.Index
    }

    static func chunkText(_ text: String) -> [Chunk] {
        guard text.count > maxChunkLength else {
            return [Chunk(substring: text, base: text.startIndex)]
        }
        var chunks: [Chunk] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxChunkLength, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(Chunk(substring: String(text[start..<end]), base: start))
            if end == text.endIndex { break }
            let overlap = text.index(end, offsetBy: -200, limitedBy: start) ?? start
            start = overlap
        }
        return chunks
    }

    static func remap(_ entities: [SensitiveEntity], chunk: Chunk, in text: String) -> [SensitiveEntity] {
        entities.compactMap { entity in
            // Entity ranges belong to `chunk.substring`, so offsets must be measured against it;
            // mixing those indices with `text` APIs is undefined and drifts on non-ASCII content.
            let lowerOffset = chunk.substring.distance(from: chunk.substring.startIndex, to: entity.range.lowerBound)
            let upperOffset = chunk.substring.distance(from: chunk.substring.startIndex, to: entity.range.upperBound)
            guard
                let lower = text.index(chunk.base, offsetBy: lowerOffset, limitedBy: text.endIndex),
                let upper = text.index(chunk.base, offsetBy: upperOffset, limitedBy: text.endIndex),
                lower < upper
            else { return nil }
            let range = lower..<upper
            return SensitiveEntity(
                id: entity.id,
                type: entity.type,
                range: range,
                value: String(text[range]),
                confidence: entity.confidence,
                source: entity.source
            )
        }
    }

    private static func mapType(_ raw: String) -> SensitiveEntityType? {
        if let mapped = NERLabelMapper.defaultEntityType(for: raw) {
            return mapped
        }
        switch raw.uppercased() {
        case "ORGANIZATION", "ORG", "COMPANY":
            return .customCompany
        case "CREDIT_CARD", "CARD":
            return .creditCardLike
        case "SENSITIVE_TERM", "MISC":
            return .customSensitiveTerm
        default:
            return nil
        }
    }

    private static func extractJSONData(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) {
            return data
        }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else { return nil }
        return String(trimmed[start...end]).data(using: .utf8)
    }

    private static func firstRange(
        of needle: String,
        in text: String,
        excluding used: [Range<String.Index>]
    ) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let found = text.range(of: needle, range: searchStart..<text.endIndex) {
            if !used.contains(where: { $0.overlaps(found) }) {
                return found
            }
            searchStart = found.upperBound
        }
        return nil
    }
}
