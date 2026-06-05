import Foundation

public struct DetectionRequest {
    public let text: String
    public let options: DetectionOptions

    public init(text: String, options: DetectionOptions = .default) {
        self.text = text
        self.options = options
    }
}

public struct DetectionOptions: Equatable {
    public var enabledTypes: Set<SensitiveEntityType>
    public var customDictionaries: [CustomDictionaryItem]
    public var maximumLength: Int

    public init(
        enabledTypes: Set<SensitiveEntityType> = Set(SensitiveEntityType.allCases),
        customDictionaries: [CustomDictionaryItem] = [],
        maximumLength: Int = 50_000
    ) {
        self.enabledTypes = enabledTypes
        self.customDictionaries = customDictionaries
        self.maximumLength = maximumLength
    }

    public static let `default` = DetectionOptions()
}

public struct DetectionResult {
    /// Entity ranges are valid **only** against `scannedText`, never the original input.
    /// When `wasTruncated` is true, `scannedText` is shorter than the source and only it was scanned.
    public let entities: [SensitiveEntity]
    public let scannedText: String
    public let wasTruncated: Bool
    public let scannedCharacterCount: Int

    public init(entities: [SensitiveEntity], scannedText: String, wasTruncated: Bool, scannedCharacterCount: Int) {
        self.entities = entities
        self.scannedText = scannedText
        self.wasTruncated = wasTruncated
        self.scannedCharacterCount = scannedCharacterCount
    }
}

public struct SensitiveEntity: Identifiable, Equatable {
    public let id: UUID
    public let type: SensitiveEntityType
    /// Valid only against `DetectionResult.scannedText`; using it on any other string is undefined.
    public let range: Range<String.Index>
    public let value: String
    public let confidence: Double
    public let source: DetectionSource

    public init(
        id: UUID = UUID(),
        type: SensitiveEntityType,
        range: Range<String.Index>,
        value: String,
        confidence: Double,
        source: DetectionSource
    ) {
        self.id = id
        self.type = type
        self.range = range
        self.value = value
        self.confidence = confidence
        self.source = source
    }
}

public enum SensitiveEntityType: String, CaseIterable, Codable, Hashable, Sendable {
    case email
    case phone
    case money
    case url
    case ipAddress
    case internalDomain
    case contractId
    case invoiceId
    case orderId
    case apiKeyGeneric
    case openAIAPIKey
    case awsAccessKeyId
    case githubToken
    case slackToken
    case stripeKey
    case jwt
    case privateKey
    case sshPrivateKey
    case databaseURLWithPassword
    case bearerToken
    case highEntropyString
    case creditCardLike
    case iban
    case customClient
    case customCompany
    case customProject
    case customSensitiveTerm
    case customInternalDomain

    public var placeholderPrefix: String {
        switch self {
        case .email:
            return "EMAIL"
        case .phone:
            return "PHONE"
        case .money:
            return "AMOUNT"
        case .url:
            return "URL"
        case .ipAddress:
            return "IP"
        case .internalDomain, .customInternalDomain:
            return "INTERNAL_DOMAIN"
        case .contractId:
            return "CONTRACT"
        case .invoiceId:
            return "INVOICE"
        case .orderId:
            return "ORDER"
        case .creditCardLike:
            return "CARD"
        case .iban:
            return "IBAN"
        case .customClient:
            return "CLIENT"
        case .customCompany:
            return "COMPANY"
        case .customProject:
            return "PROJECT"
        case .customSensitiveTerm:
            return "CUSTOM"
        default:
            return "SECRET"
        }
    }

    public var isSecret: Bool {
        switch self {
        case .apiKeyGeneric, .openAIAPIKey, .awsAccessKeyId, .githubToken, .slackToken,
             .stripeKey, .jwt, .privateKey, .sshPrivateKey, .databaseURLWithPassword,
             .bearerToken, .highEntropyString:
            return true
        default:
            return false
        }
    }

    /// High-confidence secret shapes (keys, JWT, `Bearer …`). Excludes `.highEntropyString`, which is a fuzzy length/heuristic match and causes many false positives on ordinary text.
    public var countsAsCriticalSecret: Bool {
        isSecret && self != .highEntropyString
    }
}

public enum DetectionSource: String, Codable, Equatable, Sendable {
    case regex
    case secret
    case customDictionary
}

public enum CustomDictionaryKind: String, Codable, CaseIterable, Hashable {
    case client
    case company
    case project
    case sensitiveTerm
    case internalDomain

    public var entityType: SensitiveEntityType {
        switch self {
        case .client:
            return .customClient
        case .company:
            return .customCompany
        case .project:
            return .customProject
        case .sensitiveTerm:
            return .customSensitiveTerm
        case .internalDomain:
            return .customInternalDomain
        }
    }
}

public struct CustomDictionaryItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var kind: CustomDictionaryKind
    public var value: String
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: CustomDictionaryKind, value: String, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.value = value
        self.createdAt = createdAt
    }
}

public enum RiskLevel: String, Codable, Equatable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical
}

public enum RecommendedAction: String, Codable, Equatable, Sendable {
    case allow
    case warn
    case mask
    case block
}
