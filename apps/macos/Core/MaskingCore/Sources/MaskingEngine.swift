import DetectionCore
import Foundation

public struct MaskingResult: Codable, Equatable, Identifiable, Sendable {
    /// Explicit lifetime of a mapping. `.ephemeral` means "never persist" — distinct from
    /// an expiry date, so consumers don't have to overload `expiresAt == nil`.
    public enum Retention: Codable, Equatable, Sendable {
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
