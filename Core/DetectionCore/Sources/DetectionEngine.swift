import Foundation

public protocol SensitiveDataDetecting {
    func scan(_ request: DetectionRequest) -> DetectionResult
}

public final class DetectionEngine: SensitiveDataDetecting {
    private let regexRules: [DetectionRule]
    private let secretRules: [DetectionRule]

    public init() {
        self.regexRules = DetectionRule.regexRules
        self.secretRules = DetectionRule.secretRules
    }

    public func scan(_ request: DetectionRequest) -> DetectionResult {
        let normalized = TextNormalizer.normalize(request.text, maximumLength: request.options.maximumLength)
        guard !normalized.text.isEmpty else {
            return DetectionResult(entities: [], scannedText: normalized.text, wasTruncated: normalized.wasTruncated, scannedCharacterCount: 0)
        }

        var entities: [SensitiveEntity] = []
        entities += scanRules(regexRules, in: normalized.text, options: request.options)
        entities += scanRules(secretRules, in: normalized.text, options: request.options)
        entities += scanCustomDictionaries(request.options.customDictionaries, in: normalized.text, options: request.options)

        let merged = OverlapResolver.resolve(entities, in: normalized.text)
        let filtered = Self.filterFalsePositiveHighEntropyStrings(
            Self.filterFalsePositiveMoney(Self.filterFalsePositivePhones(merged))
        )
        return DetectionResult(
            entities: filtered,
            scannedText: normalized.text,
            wasTruncated: normalized.wasTruncated,
            scannedCharacterCount: normalized.text.count
        )
    }

    private static func filterFalsePositiveMoney(_ entities: [SensitiveEntity]) -> [SensitiveEntity] {
        entities.filter { entity in
            guard entity.type == .money else { return true }
            return !MoneyMatchSanitizer.shouldRejectMoneyValue(entity.value)
        }
    }

    private static func filterFalsePositivePhones(_ entities: [SensitiveEntity]) -> [SensitiveEntity] {
        entities.filter { entity in
            guard entity.type == .phone else { return true }
            return !PhoneMatchSanitizer.shouldRejectPhoneValue(entity.value)
        }
    }

    private static func filterFalsePositiveHighEntropyStrings(_ entities: [SensitiveEntity]) -> [SensitiveEntity] {
        entities.filter { entity in
            guard entity.type == .highEntropyString else { return true }
            return !HighEntropyMatchSanitizer.shouldRejectHighEntropyValue(entity.value)
        }
    }

    private func scanRules(_ rules: [DetectionRule], in text: String, options: DetectionOptions) -> [SensitiveEntity] {
        rules
            .filter { options.enabledTypes.contains($0.type) }
            .flatMap { rule in rule.matches(in: text) }
    }

    private func scanCustomDictionaries(
        _ dictionaries: [CustomDictionaryItem],
        in text: String,
        options: DetectionOptions
    ) -> [SensitiveEntity] {
        dictionaries.flatMap { item -> [SensitiveEntity] in
            let type = item.kind.entityType
            guard options.enabledTypes.contains(type) else { return [] }
            let escaped = NSRegularExpression.escapedPattern(for: item.value.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !escaped.isEmpty else { return [] }
            let pattern = item.kind == .internalDomain ? escaped : "\\b\(escaped)\\b"
            let rule = DetectionRule(type: type, source: .customDictionary, pattern: pattern, confidence: 0.95)
            return rule.matches(in: text)
        }
    }
}

private struct NormalizedText {
    let text: String
    let wasTruncated: Bool
}

/// Swift/Ruby-style `$0`…`$9` closure args match `[$]\d`, but are almost never lone sub-dollar amounts (`$50` stays).
private enum MoneyMatchSanitizer {
    private static let singleDigitAfterDollar = try! NSRegularExpression(pattern: #"^\$\d$"#, options: [])

    static func shouldRejectMoneyValue(_ value: String) -> Bool {
        singleDigitAfterDollar.firstMatch(in: value, options: [], range: NSRange(value.startIndex..<value.endIndex, in: value)) != nil
    }
}

/// Values that accidentally match the loose phone regex (e.g. ISO dates in `photo_YYYY-MM-DD…`).
private enum PhoneMatchSanitizer {
    private static let isoCalendarDateDash = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
    private static let isoCalendarDateDots = try! NSRegularExpression(pattern: #"^\d{4}\.\d{2}\.\d{2}$"#)
    /// Fragment like `16.50.15` in camera filenames (clock), not a phone number.
    private static let clockTimeDots = try! NSRegularExpression(pattern: #"^(?:[01]?\d|2[0-3])\.[0-5]\d\.[0-5]\d$"#)
    /// `node-id=44305-5998` (Figma), US ZIP+4, and similar IDs — not phone numbers.
    private static let fiveDigitsDashFourDigits = try! NSRegularExpression(pattern: #"^\d{5}-\d{4}$"#)
    /// E.164 allows at most 15 digits; 16+ with only digit/separator characters is almost always a PAN-like token (e.g. `4242 4242 4242 4242`).
    private static var digitSeparatorPhoneShape: CharacterSet {
        var set = CharacterSet.decimalDigits
        set.formUnion(.whitespacesAndNewlines)
        set.insert(charactersIn: ".-+()")
        return set
    }

    /// Same shape as `DetectionRule` IPv4; loose phone regex matches dotted quads and prefixes like `104.16.175`.
    private static let ipv4Address = try! NSRegularExpression(
        pattern: #"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$"#,
        options: []
    )

    static func shouldRejectPhoneValue(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        if isoCalendarDateDash.firstMatch(in: value, options: [], range: range) != nil { return true }
        if isoCalendarDateDots.firstMatch(in: value, options: [], range: range) != nil { return true }
        if clockTimeDots.firstMatch(in: value, options: [], range: range) != nil { return true }
        if fiveDigitsDashFourDigits.firstMatch(in: value, options: [], range: range) != nil { return true }
        if ipv4Address.firstMatch(in: value, options: [], range: range) != nil { return true }
        if shouldRejectTooManyDigitsForE164PhoneShape(value) { return true }
        return false
    }

    private static func shouldRejectTooManyDigitsForE164PhoneShape(_ value: String) -> Bool {
        let digitCount = value.filter(\.isNumber).count
        guard digitCount >= 16 else { return false }
        return value.unicodeScalars.allSatisfy { digitSeparatorPhoneShape.contains($0) }
    }
}

/// `highEntropyString` allows `/`, so multi-segment URL paths (e.g. Figma file URLs) match as one token.
private enum HighEntropyMatchSanitizer {
    static func shouldRejectHighEntropyValue(_ value: String) -> Bool {
        value.filter { $0 == "/" }.count >= 2
    }
}

private enum TextNormalizer {
    static func normalize(_ text: String, maximumLength: Int) -> NormalizedText {
        guard text.count > maximumLength else {
            return NormalizedText(text: text, wasTruncated: false)
        }
        let limited = String(text.prefix(maximumLength))
        return NormalizedText(text: limited, wasTruncated: text.count > maximumLength)
    }
}

public struct DetectionRule: Equatable {
    public let type: SensitiveEntityType
    public let source: DetectionSource
    public let pattern: String
    public let confidence: Double
    public let options: NSRegularExpression.Options

    public init(
        type: SensitiveEntityType,
        source: DetectionSource,
        pattern: String,
        confidence: Double,
        options: NSRegularExpression.Options = [.caseInsensitive]
    ) {
        self.type = type
        self.source = source
        self.pattern = pattern
        self.confidence = confidence
        self.options = options
    }

    public func matches(in text: String) -> [SensitiveEntity] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text), !range.isEmpty else { return nil }
            let value = String(text[range])
            return SensitiveEntity(type: type, range: range, value: value, confidence: confidence, source: source)
        }
    }
}

public extension DetectionRule {
    static let regexRules: [DetectionRule] = [
        .init(type: .email, source: .regex, pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, confidence: 0.98),
        .init(type: .phone, source: .regex, pattern: #"(?:\+?\d{1,3}[\s.-]?)?(?:\(?\d{2,4}\)?[\s.-]?)?\d{3}[\s.-]?\d{2,4}[\s.-]?\d{2,4}\b"#, confidence: 0.75),
        .init(type: .money, source: .regex, pattern: #"(?:[$€£₽]\s?\d{1,3}(?:[,\s]\d{3})*(?:\.\d{2})?|\d{1,3}(?:[,\s]\d{3})*(?:\.\d{2})?\s?(?:USD|EUR|GBP|RUB|руб\.?))\b"#, confidence: 0.85),
        .init(type: .url, source: .regex, pattern: #"\bhttps?://[^\s<>"']+"#, confidence: 0.85),
        .init(type: .ipAddress, source: .regex, pattern: #"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#, confidence: 0.9),
        .init(type: .internalDomain, source: .regex, pattern: #"\b(?:[a-z0-9-]+\.)+(?:internal|local|corp|lan|intranet)\b"#, confidence: 0.9),
        .init(type: .contractId, source: .regex, pattern: #"\b(?:CN|CONTRACT|CTR|AGR)[-_]?\d{3,10}\b"#, confidence: 0.9),
        .init(type: .invoiceId, source: .regex, pattern: #"\b(?:INV|INVOICE)[-_]?\d{3,10}\b"#, confidence: 0.9),
        .init(type: .orderId, source: .regex, pattern: #"\b(?:ORD|ORDER)[-_]?\d{3,10}\b"#, confidence: 0.85),
        .init(type: .creditCardLike, source: .regex, pattern: #"\b(?:\d[ -]*?){13,19}\b"#, confidence: 0.75),
        .init(type: .iban, source: .regex, pattern: #"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b"#, confidence: 0.85)
    ]

    static let secretRules: [DetectionRule] = [
        .init(type: .openAIAPIKey, source: .secret, pattern: #"\bsk-[A-Za-z0-9_-]{32,}\b"#, confidence: 0.99),
        .init(type: .awsAccessKeyId, source: .secret, pattern: #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#, confidence: 0.99),
        .init(type: .githubToken, source: .secret, pattern: #"\bgh[pousr]_[A-Za-z0-9_]{30,255}\b"#, confidence: 0.99),
        .init(type: .slackToken, source: .secret, pattern: #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#, confidence: 0.99),
        .init(type: .stripeKey, source: .secret, pattern: #"\b(?:sk|pk)_(?:live|test)_[A-Za-z0-9]{16,}\b"#, confidence: 0.98),
        .init(type: .jwt, source: .secret, pattern: #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, confidence: 0.98),
        .init(type: .privateKey, source: .secret, pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, confidence: 1.0, options: []),
        .init(type: .sshPrivateKey, source: .secret, pattern: #"-----BEGIN OPENSSH PRIVATE KEY-----[\s\S]*?-----END OPENSSH PRIVATE KEY-----"#, confidence: 1.0, options: []),
        .init(type: .databaseURLWithPassword, source: .secret, pattern: #"\b(?:postgres|postgresql|mysql|mongodb|redis)://[^:\s/@]+:[^@\s]+@[^\s]+"#, confidence: 0.99),
        .init(type: .bearerToken, source: .secret, pattern: #"\bBearer\s+[A-Za-z0-9._~+/=-]{20,}\b"#, confidence: 0.95),
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\b(?:api[_-]?key|secret|token|client[_-]?secret)\s*[:=]\s*['"]?[A-Za-z0-9._~+/=-]{20,}['"]?"#, confidence: 0.9),
        .init(type: .highEntropyString, source: .secret, pattern: #"\b[A-Za-z0-9+/=_-]{40,}\b"#, confidence: 0.65)
    ]
}

public enum OverlapResolver {
    public static func resolve(_ entities: [SensitiveEntity], in text: String) -> [SensitiveEntity] {
        let sorted = entities.sorted { lhs, rhs in
            if lhs.range.lowerBound == rhs.range.lowerBound {
                return priority(lhs) > priority(rhs)
            }
            return lhs.range.lowerBound < rhs.range.lowerBound
        }

        return sorted.reduce(into: [SensitiveEntity]()) { result, entity in
            guard let last = result.last else {
                result.append(entity)
                return
            }

            if last.range.overlaps(entity.range) {
                if priority(entity) > priority(last) {
                    result.removeLast()
                    result.append(entity)
                }
            } else {
                result.append(entity)
            }
        }
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
        case .regex:
            return 100
        case .secret:
            return 1_000
        }
    }
}
