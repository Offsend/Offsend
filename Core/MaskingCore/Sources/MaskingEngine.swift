import DetectionCore
import Foundation

public struct MaskingResult: Codable, Equatable, Identifiable {
    /// Explicit lifetime of a mapping. `.ephemeral` means "never persist" — distinct from
    /// an expiry date, so consumers don't have to overload `expiresAt == nil`.
    public enum Retention: Codable, Equatable {
        case ephemeral
        case expiring(Date)
    }

    public let id: UUID
    public let maskedText: String
    public let mapping: [String: String]
    public let createdAt: Date
    public let retention: Retention

    /// Expiry date for persisted mappings; `nil` for ephemeral ones.
    public var expiresAt: Date? {
        if case .expiring(let date) = retention { return date }
        return nil
    }

    /// Whether the mapping is allowed to be stored at all.
    public var shouldPersist: Bool {
        if case .ephemeral = retention { return false }
        return true
    }

    public init(
        id: UUID = UUID(),
        maskedText: String,
        mapping: [String: String],
        createdAt: Date = Date(),
        retention: Retention = .ephemeral
    ) {
        self.id = id
        self.maskedText = maskedText
        self.mapping = mapping
        self.createdAt = createdAt
        self.retention = retention
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

    public static let freeTierOptions: [MappingTTL] = [.oneHour]

    public static func allowedOptions(extendedTTLAllowed: Bool) -> [MappingTTL] {
        extendedTTLAllowed ? Array(allCases) : freeTierOptions
    }

    public static func effective(_ selected: MappingTTL, extendedTTLAllowed: Bool) -> MappingTTL {
        guard extendedTTLAllowed else { return .oneHour }
        return selected
    }
}

public protocol TextMasking: Sendable {
    func mask(text: String, entities: [SensitiveEntity], ttl: MappingTTL) -> MaskingResult
    func restore(text: String, mapping: [String: String]) -> String
}

public final class MaskingEngine: TextMasking {
    public init() {}

    public func mask(text: String, entities: [SensitiveEntity], ttl: MappingTTL = .oneHour) -> MaskingResult {
        let orderedEntities = entities.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var counters: [String: Int] = [:]
        var placeholderByValue: [String: String] = [:]
        var replacements: [(range: Range<String.Index>, placeholder: String, value: String)] = []
        var coveredUpperBound: String.Index?

        for entity in orderedEntities {
            // Range must be valid for `text` and actually cover `entity.value`; otherwise
            // `replaceSubrange` would corrupt output or crash (e.g. ranges from a different
            // or truncated source text).
            guard entity.range.lowerBound >= text.startIndex,
                  entity.range.upperBound <= text.endIndex,
                  text[entity.range] == entity.value else { continue }

            // Drop ranges overlapping an already-accepted replacement; reversed
            // `replaceSubrange` requires non-overlapping ranges.
            if let upper = coveredUpperBound, entity.range.lowerBound < upper { continue }

            let placeholder: String
            if let existing = placeholderByValue[entity.value] {
                placeholder = existing
            } else {
                let prefix = entity.type.placeholderPrefix
                let next = (counters[prefix] ?? 0) + 1
                counters[prefix] = next
                placeholder = "{{\(prefix)_\(next)}}"
                placeholderByValue[entity.value] = placeholder
            }
            replacements.append((entity.range, placeholder, entity.value))
            coveredUpperBound = Swift.max(coveredUpperBound ?? entity.range.upperBound, entity.range.upperBound)
        }

        var maskedText = text
        for replacement in replacements.reversed() {
            maskedText.replaceSubrange(replacement.range, with: replacement.placeholder)
        }

        let mapping = Dictionary(uniqueKeysWithValues: placeholderByValue.map { ($0.value, $0.key) })
        let retention: MaskingResult.Retention = ttl.interval
            .map { .expiring(Date().addingTimeInterval($0)) } ?? .ephemeral
        return MaskingResult(maskedText: maskedText, mapping: mapping, retention: retention)
    }

    public func restore(text: String, mapping: [String: String]) -> String {
        mapping.reduce(text) { restored, entry in
            restored.replacingOccurrences(of: entry.key, with: entry.value)
        }
    }
}
