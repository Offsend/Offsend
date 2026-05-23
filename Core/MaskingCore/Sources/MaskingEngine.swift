import DetectionCore
import Foundation

public struct MaskingResult: Codable, Equatable, Identifiable {
    public let id: UUID
    public let maskedText: String
    public let mapping: [String: String]
    public let createdAt: Date
    public let expiresAt: Date?

    public init(
        id: UUID = UUID(),
        maskedText: String,
        mapping: [String: String],
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.maskedText = maskedText
        self.mapping = mapping
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public enum MappingTTL: String, Codable, CaseIterable, Identifiable, Sendable {
    case oneHour
    case sixHours
    case twentyFourHours
    case neverStore

    public var id: String { rawValue }

    public var interval: TimeInterval? {
        switch self {
        case .oneHour:
            return 3_600
        case .sixHours:
            return 21_600
        case .twentyFourHours:
            return 86_400
        case .neverStore:
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .oneHour:
            return MaskingCoreStrings.mappingTTLOneHour
        case .sixHours:
            return MaskingCoreStrings.mappingTTLSixHours
        case .twentyFourHours:
            return MaskingCoreStrings.mappingTTLTwentyFourHours
        case .neverStore:
            return MaskingCoreStrings.mappingTTLNeverStore
        }
    }
}

public protocol TextMasking {
    func mask(text: String, entities: [SensitiveEntity], ttl: MappingTTL) -> MaskingResult
    func restore(text: String, mapping: [String: String]) -> String
}

public final class MaskingEngine: TextMasking {
    public init() {}

    public func mask(text: String, entities: [SensitiveEntity], ttl: MappingTTL = .sixHours) -> MaskingResult {
        let orderedEntities = entities.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var counters: [String: Int] = [:]
        var replacements: [(range: Range<String.Index>, placeholder: String, value: String)] = []

        for entity in orderedEntities {
            let prefix = entity.type.placeholderPrefix
            let next = (counters[prefix] ?? 0) + 1
            counters[prefix] = next
            replacements.append((entity.range, "{{\(prefix)_\(next)}}", entity.value))
        }

        var maskedText = text
        for replacement in replacements.reversed() {
            maskedText.replaceSubrange(replacement.range, with: replacement.placeholder)
        }

        let mapping = Dictionary(uniqueKeysWithValues: replacements.map { ($0.placeholder, $0.value) })
        let expiration = ttl.interval.map { Date().addingTimeInterval($0) }
        return MaskingResult(maskedText: maskedText, mapping: mapping, expiresAt: expiration)
    }

    public func restore(text: String, mapping: [String: String]) -> String {
        mapping.reduce(text) { restored, entry in
            restored.replacingOccurrences(of: entry.key, with: entry.value)
        }
    }
}
