import Foundation

public protocol SensitiveDataDetecting: Sendable {
    func scan(_ request: DetectionRequest) async -> DetectionResult
}

public final class DetectionEngine: SensitiveDataDetecting, @unchecked Sendable {
    private let regexRules: [CompiledRule]
    private let secretRules: [CompiledRule]
    private let aiDetector: (any AIModelDetecting)?

    public init(aiDetector: (any AIModelDetecting)? = nil) {
        self.regexRules = DetectionRule.regexRules.map(CompiledRule.init)
        self.secretRules = DetectionRule.secretRules.map(CompiledRule.init)
        self.aiDetector = aiDetector
    }

    public func scan(_ request: DetectionRequest) async -> DetectionResult {
        let normalized = TextNormalizer.normalize(request.text, maximumLength: request.options.maximumLength)
        guard !normalized.text.isEmpty else {
            return DetectionResult(entities: [], scannedText: normalized.text, wasTruncated: normalized.wasTruncated, scannedCharacterCount: 0)
        }

        DetectionDebugLogger.logScanStart(
            characterCount: normalized.text.count,
            wasTruncated: normalized.wasTruncated,
            aiEnabled: request.options.aiDetectionEnabled,
            selectedAIModelID: request.options.selectedAIModelID
        )

        let regexEntities = scanRules(regexRules, in: normalized.text, options: request.options)
        DetectionDebugLogger.logPhase("regex", entities: regexEntities, in: normalized.text)

        let secretEntities = scanRules(secretRules, in: normalized.text, options: request.options)
        DetectionDebugLogger.logPhase("secret", entities: secretEntities, in: normalized.text)

        let dictionaryEntities = scanCustomDictionaries(
            request.options.customDictionaries,
            in: normalized.text,
            options: request.options
        )
        DetectionDebugLogger.logPhase("customDictionary", entities: dictionaryEntities, in: normalized.text)

        var entities = regexEntities + secretEntities + dictionaryEntities

        var aiDetectionError: String?
        if request.options.aiDetectionEnabled {
            if let aiDetector {
                do {
                    let aiEntities = try await aiDetector.detect(text: normalized.text, options: request.options)
                    let filteredAI = aiEntities.filter { request.options.enabledTypes.contains($0.type) }
                    DetectionDebugLogger.logPhase("ai", entities: filteredAI, in: normalized.text)
                    entities += filteredAI
                } catch {
                    aiDetectionError = Self.localizedDetectionError(error)
                    DetectionDebugLogger.logAIDetectionError(aiDetectionError ?? error.localizedDescription)
                }
            } else {
                aiDetectionError = AIModelRuntimeError.modelNotLoaded.errorDescription
                DetectionDebugLogger.logAIDetectionError(aiDetectionError ?? "model not loaded")
            }
        }

        let merged = OverlapResolver.resolve(entities, in: normalized.text)
        DetectionDebugLogger.logPhase("merged", entities: merged, in: normalized.text)

        let afterPhoneFilter = Self.filterFalsePositivePhones(merged)
        let afterMoneyFilter = Self.filterFalsePositiveMoney(afterPhoneFilter)
        let filtered = Self.filterFalsePositiveHighEntropyStrings(afterMoneyFilter)
        let removed = merged.filter { candidate in
            !filtered.contains { $0.id == candidate.id }
        }
        DetectionDebugLogger.logFilteredOut(removed, in: normalized.text)
        DetectionDebugLogger.logPhase("final", entities: filtered, in: normalized.text)

        return DetectionResult(
            entities: filtered,
            scannedText: normalized.text,
            wasTruncated: normalized.wasTruncated,
            scannedCharacterCount: normalized.text.count,
            aiDetectionError: aiDetectionError
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

    private func scanRules(_ rules: [CompiledRule], in text: String, options: DetectionOptions) -> [SensitiveEntity] {
        rules
            .filter { options.enabledTypes.contains($0.rule.type) }
            .flatMap { rule in rule.matches(in: text) }
    }

    private static func localizedDetectionError(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func scanCustomDictionaries(
        _ dictionaries: [CustomDictionaryItem],
        in text: String,
        options: DetectionOptions
    ) -> [SensitiveEntity] {
        dictionaries.flatMap { item -> [SensitiveEntity] in
            let type = item.kind.entityType
            guard options.enabledTypes.contains(type) else { return [] }
            guard let rule = CustomDictionaryRuleCache.rule(for: item) else { return [] }
            return rule.matches(in: text)
        }
    }
}

enum CustomDictionaryRuleCache {
    /// Hard cap so entries removed from the user's dictionaries can't accumulate forever.
    private static let maxEntries = 512
    private static let lock = NSLock()
    private static var rules: [String: CompiledRule] = [:]

    static func rule(for item: CustomDictionaryItem) -> CompiledRule? {
        let trimmed = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = "\(item.kind.rawValue):\(trimmed)"

        return lock.withLock {
            if let cached = rules[key] {
                return cached
            }
            if rules.count >= maxEntries {
                rules.removeAll(keepingCapacity: true)
            }

            let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            guard !escaped.isEmpty else { return nil }
            // Domain values must not match as a substring of a larger host (`acme.internal`
            // inside `notacme.internalx`); other values use word boundaries.
            let pattern = item.kind == .internalDomain
                ? "(?<![A-Za-z0-9.-])\(escaped)(?![A-Za-z0-9.-])"
                : "\\b\(escaped)\\b"
            let detectionRule = DetectionRule(
                type: item.kind.entityType,
                source: .customDictionary,
                pattern: pattern,
                confidence: 0.95
            )
            let compiled = CompiledRule(detectionRule)
            rules[key] = compiled
            return compiled
        }
    }

    static var entryCount: Int {
        lock.withLock { rules.count }
    }

    static func resetForTesting() {
        lock.withLock { rules.removeAll() }
    }
}

/// Caches the compiled `NSRegularExpression` so a pattern is compiled once, not on every scan.
/// Compilation failures surface in debug instead of being silently swallowed.
final class CompiledRule: @unchecked Sendable {
    let rule: DetectionRule
    private let regex: NSRegularExpression?

    init(_ rule: DetectionRule) {
        self.rule = rule
        do {
            self.regex = try NSRegularExpression(pattern: rule.pattern, options: rule.options)
        } catch {
            assertionFailure("Invalid detection pattern for \(rule.type): \(error)")
            self.regex = nil
        }
    }

    func matches(in text: String) -> [SensitiveEntity] {
        guard let regex else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text), !range.isEmpty else { return nil }
            let value = String(text[range])
            return SensitiveEntity(type: rule.type, range: range, value: value, confidence: rule.confidence, source: rule.source)
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

/// `highEntropyString` allows `/`, so multi-segment URL paths can match as one token. Base64
/// (e.g. Sparkle `edSignature`) also contains `/`; reject URL-shaped paths, not slash count alone.
private enum HighEntropyMatchSanitizer {
    static func shouldRejectHighEntropyValue(_ value: String) -> Bool {
        if value.contains("://") { return true }
        let slashCount = value.filter { $0 == "/" }.count
        return slashCount >= 2 && value.contains(".")
    }
}

private enum TextNormalizer {
    /// Only the returned text is scanned. Anything past `maximumLength` is **not** examined, so
    /// callers must treat `wasTruncated == true` as "input not fully sanitized". We cut on a
    /// whitespace boundary when one exists so a token (e.g. a secret) is never split into a
    /// partial, mis-detected fragment at the edge; without a boundary we fall back to a hard cut.
    static func normalize(_ text: String, maximumLength: Int) -> NormalizedText {
        guard text.count > maximumLength else {
            return NormalizedText(text: text, wasTruncated: false)
        }
        let hardLimit = text.index(text.startIndex, offsetBy: maximumLength)
        let cut = tokenBoundary(in: text, before: hardLimit) ?? hardLimit
        return NormalizedText(text: String(text[..<cut]), wasTruncated: true)
    }

    /// Last whitespace at or before `limit`; `nil` when the only boundary would leave an empty prefix.
    private static func tokenBoundary(in text: String, before limit: String.Index) -> String.Index? {
        guard let boundary = text[..<limit].lastIndex(where: \.isWhitespace), boundary > text.startIndex else {
            return nil
        }
        return boundary
    }
}

public struct DetectionRule: Equatable, Sendable {
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
        // Leading `(?<![A-Za-z0-9])` stops a phone from starting mid-token; separators exclude line
        // breaks (a phone never wraps a line) so a stray match can't bridge entities across newlines.
        .init(type: .phone, source: .regex, pattern: #"(?<![A-Za-z0-9])(?:\+?\d{1,3}[ \t.\-]?)?(?:\(?\d{2,4}\)?[ \t.\-]?)?\d{3}[ \t.\-]?\d{2,4}[ \t.\-]?\d{2,4}\b"#, confidence: 0.75),
        // Separators use `[^\S\r\n]` (whitespace except line breaks): an amount never wraps a line,
        // so a stray match can't bridge entities across newlines after overlap merging.
        .init(type: .money, source: .regex, pattern: #"(?:[$€£₽][^\S\r\n]?\d{1,3}(?:(?:,|[^\S\r\n])\d{3})*(?:\.\d{2})?|\d{1,3}(?:(?:,|[^\S\r\n])\d{3})*(?:\.\d{2})?[^\S\r\n]?(?:USD|EUR|GBP|RUB|руб\.?))\b"#, confidence: 0.85),
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
        // Lookarounds instead of `\b`: `+`, `/`, and `=` are non-word, so `\b` truncates base64 padding (`==`).
        // `=` is already in the class, so trailing padding is consumed by the main quantifier.
        .init(type: .highEntropyString, source: .secret, pattern: #"(?<![A-Za-z0-9+/=_-])[A-Za-z0-9+/=_-]{40,}(?![A-Za-z0-9+/=_-])"#, confidence: 0.65)
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
