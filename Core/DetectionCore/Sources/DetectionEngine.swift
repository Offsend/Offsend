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
        let text = normalized.text
        guard !text.isEmpty else {
            return DetectionResult(entities: [], scannedText: text, wasTruncated: normalized.wasTruncated, scannedCharacterCount: 0)
        }

        DetectionDebugLogger.logScanStart(
            characterCount: text.count,
            wasTruncated: normalized.wasTruncated,
            aiEnabled: request.options.aiDetectionEnabled,
            selectedAIModelID: request.options.selectedAIModelID
        )

        // Deterministic detectors scan the full text in overlapping windows, so nothing is silently
        // dropped past `maximumLength` (the old behavior). The window only bounds per-pass regex cost.
        let window = request.options.maximumLength
        let regexEntities = scanRules(regexRules, in: text, window: window, options: request.options)
        DetectionDebugLogger.logPhase("regex", entities: regexEntities, in: text)

        let secretEntities = scanRules(secretRules, in: text, window: window, options: request.options)
        DetectionDebugLogger.logPhase("secret", entities: secretEntities, in: text)

        let dictionaryEntities = scanCustomDictionaries(
            request.options.customDictionaries,
            in: text,
            window: window,
            options: request.options
        )
        DetectionDebugLogger.logPhase("customDictionary", entities: dictionaryEntities, in: text)

        var entities = regexEntities + secretEntities + dictionaryEntities

        var aiDetectionError: String?
        if request.options.aiDetectionEnabled {
            if let aiDetector {
                do {
                    // AI inference stays bounded to a prefix (cost guard); ranges are remapped back onto
                    // the full text so they remain valid against `scannedText`.
                    let aiText = normalized.wasTruncated ? String(text.prefix(window)) : text
                    let aiEntities = try await aiDetector.detect(text: aiText, options: request.options)
                    let mappedAI = normalized.wasTruncated ? Self.remap(aiEntities, from: aiText, to: text) : aiEntities
                    let filteredAI = mappedAI.filter { request.options.enabledTypes.contains($0.type) }
                    DetectionDebugLogger.logPhase("ai", entities: filteredAI, in: text)
                    entities += filteredAI
                } catch {
                    aiDetectionError = Self.localizedDetectionError(error)
                    DetectionDebugLogger.logAIDetectionError(aiDetectionError ?? error.localizedDescription)
                }
            } else {
                aiDetectionError = "AI model is not loaded."
                DetectionDebugLogger.logAIDetectionError(aiDetectionError ?? "model not loaded")
            }
        }

        let merged = OverlapResolver.resolve(entities, in: text)
        DetectionDebugLogger.logPhase("merged", entities: merged, in: text)

        let afterPhoneFilter = Self.filterFalsePositivePhones(merged)
        let afterMoneyFilter = Self.filterFalsePositiveMoney(afterPhoneFilter)
        let afterCardFilter = Self.filterFalsePositiveCards(afterMoneyFilter)
        let afterIBANFilter = Self.filterFalsePositiveIBANs(afterCardFilter)
        let afterJWTFilter = Self.filterFalsePositiveJWTs(afterIBANFilter)
        let afterPlaceholderFilter = Self.filterPlaceholderSecrets(afterJWTFilter)
        let afterEntropyFilter = Self.filterFalsePositiveHighEntropyStrings(afterPlaceholderFilter)
        // Inline opt-outs are honored only for trusted file scans; never for clipboard content, where a
        // copied `offsend:ignore` could otherwise suppress masking of a real secret.
        let filtered = request.options.honorInlineIgnore
            ? Self.filterInlineIgnored(afterEntropyFilter, in: text)
            : afterEntropyFilter
        let removed = merged.filter { candidate in
            !filtered.contains { $0.id == candidate.id }
        }
        DetectionDebugLogger.logFilteredOut(removed, in: text)
        DetectionDebugLogger.logPhase("final", entities: filtered, in: text)

        return DetectionResult(
            entities: filtered,
            scannedText: text,
            wasTruncated: normalized.wasTruncated,
            scannedCharacterCount: text.count,
            aiDetectionError: aiDetectionError
        )
    }

    /// Re-anchors entities found in a prefix substring (`source`) onto the full text by character offset.
    /// The prefix shares offsets with `destination`, so a UTF-16 range in one is valid in the other.
    private static func remap(_ entities: [SensitiveEntity], from source: String, to destination: String) -> [SensitiveEntity] {
        entities.compactMap { entity in
            let nsRange = NSRange(entity.range, in: source)
            guard let range = Range(nsRange, in: destination), !range.isEmpty else { return nil }
            return SensitiveEntity(
                id: entity.id,
                type: entity.type,
                range: range,
                value: String(destination[range]),
                confidence: entity.confidence,
                source: entity.source
            )
        }
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

    /// Drops `creditCardLike` matches that fail the Luhn checksum (most random 13–19 digit runs).
    private static func filterFalsePositiveCards(_ entities: [SensitiveEntity]) -> [SensitiveEntity] {
        entities.filter { entity in
            guard entity.type == .creditCardLike else { return true }
            return !CreditCardMatchSanitizer.shouldRejectCardValue(entity.value)
        }
    }

    /// Drops `iban` matches that fail the ISO 13616 mod-97 checksum.
    private static func filterFalsePositiveIBANs(_ entities: [SensitiveEntity]) -> [SensitiveEntity] {
        entities.filter { entity in
            guard entity.type == .iban else { return true }
            return !IBANMatchSanitizer.shouldRejectIBANValue(entity.value)
        }
    }

    /// Drops `jwt` matches whose header segment is not decodable base64url JSON with an `alg` field.
    private static func filterFalsePositiveJWTs(_ entities: [SensitiveEntity]) -> [SensitiveEntity] {
        entities.filter { entity in
            guard entity.type == .jwt else { return true }
            return !JWTMatchSanitizer.shouldRejectJWTValue(entity.value)
        }
    }

    /// Drops secret matches whose value is an obvious placeholder (`<your-key>`, `xxxx…`, `changeme`).
    private static func filterPlaceholderSecrets(_ entities: [SensitiveEntity]) -> [SensitiveEntity] {
        entities.filter { entity in
            guard entity.type.isSecret else { return true }
            return !PlaceholderSecretSanitizer.isPlaceholder(entity.value)
        }
    }

    /// Suppresses entities on lines opted out via `offsend:ignore` (same line) or `offsend:ignore-next-line`.
    private static func filterInlineIgnored(_ entities: [SensitiveEntity], in text: String) -> [SensitiveEntity] {
        InlineIgnoreFilter.filter(entities, in: text)
    }

    private func scanRules(_ rules: [CompiledRule], in text: String, window: Int, options: DetectionOptions) -> [SensitiveEntity] {
        let enabled = rules.filter { options.enabledTypes.contains($0.rule.type) }
        guard !enabled.isEmpty else { return [] }
        return WindowScanner.scan(text: text, window: window) { range in
            enabled.flatMap { $0.matches(in: text, range: range) }
        }
    }

    private static func localizedDetectionError(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func scanCustomDictionaries(
        _ dictionaries: [CustomDictionaryItem],
        in text: String,
        window: Int,
        options: DetectionOptions
    ) -> [SensitiveEntity] {
        let rules = dictionaries.compactMap { item -> CompiledRule? in
            guard options.enabledTypes.contains(item.kind.entityType) else { return nil }
            return CustomDictionaryRuleCache.rule(for: item)
        }
        guard !rules.isEmpty else { return [] }
        return WindowScanner.scan(text: text, window: window) { range in
            rules.flatMap { $0.matches(in: text, range: range) }
        }
    }
}

/// Scans `text` in overlapping UTF-16 windows so very large inputs are covered in full while each regex
/// pass stays bounded. For inputs that fit in one window this is a single pass with no extra work.
enum WindowScanner {
    /// Overlap large enough to contain any single token we detect (keys, JWTs, PEM blocks fit comfortably).
    private static let maxOverlap = 8192

    static func scan(text: String, window: Int, body: (NSRange) -> [SensitiveEntity]) -> [SensitiveEntity] {
        let length = (text as NSString).length
        let windowSize = max(1, window)
        if length <= windowSize {
            return body(NSRange(location: 0, length: length))
        }

        let overlap = min(maxOverlap, max(1, windowSize / 2))
        let step = max(1, windowSize - overlap)
        var results: [SensitiveEntity] = []
        var seen = Set<String>()
        var start = 0
        while start < length {
            let len = min(windowSize, length - start)
            for entity in body(NSRange(location: start, length: len)) {
                let nsRange = NSRange(entity.range, in: text)
                let key = "\(nsRange.location):\(nsRange.length):\(entity.type.rawValue):\(entity.source.rawValue)"
                if seen.insert(key).inserted {
                    results.append(entity)
                }
            }
            if start + len >= length { break }
            start += step
        }
        return results
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

            let pattern: String
            switch item.kind {
            case .regex:
                // User-supplied pattern is used verbatim. Bail out on invalid regex so the
                // CompiledRule below never trips its debug assertion on user input.
                guard (try? NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])) != nil else {
                    return nil
                }
                pattern = trimmed
            case .internalDomain:
                let escaped = NSRegularExpression.escapedPattern(for: trimmed)
                guard !escaped.isEmpty else { return nil }
                // Domain values must not match as a substring of a larger host (`acme.internal`
                // inside `notacme.internalx`).
                pattern = "(?<![A-Za-z0-9.-])\(escaped)(?![A-Za-z0-9.-])"
            default:
                let escaped = NSRegularExpression.escapedPattern(for: trimmed)
                guard !escaped.isEmpty else { return nil }
                pattern = "\\b\(escaped)\\b"
            }
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
        matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
    }

    /// Matches only within `range`, but with transparent/non-anchoring bounds so `\b` and lookarounds
    /// still see across a window edge — letting `WindowScanner` slice large inputs without splitting tokens.
    func matches(in text: String, range: NSRange) -> [SensitiveEntity] {
        guard let regex else { return [] }
        let matchingOptions: NSRegularExpression.MatchingOptions = [.withTransparentBounds, .withoutAnchoringBounds]
        return regex.matches(in: text, options: matchingOptions, range: range).compactMap { match in
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

/// `highEntropyString` is a fuzzy length-only rule, so long source identifiers,
/// model IDs, localization keys, and URL path segments can match as soon as the precise
/// URL detector is disabled. Keep this heuristic conservative: exact secret rules catch
/// known keys, while fuzzy entropy should only catch token-like strings.
private enum HighEntropyMatchSanitizer {
    static func shouldRejectHighEntropyValue(_ value: String) -> Bool {
        if isLikelySourceIdentifier(value) { return true }
        if isPathLikeWithoutBase64Padding(value) { return true }
        let hasSecretSignal = value.contains { $0.isNumber || $0 == "+" || $0 == "=" }
        return !hasSecretSignal
    }

    private static func isLikelySourceIdentifier(_ value: String) -> Bool {
        guard let first = value.first, first.isLetter || first == "_" else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func isPathLikeWithoutBase64Padding(_ value: String) -> Bool {
        value.contains("/") && !value.contains("+") && !value.contains("=")
    }
}

/// `creditCardLike` is a loose 13–19 digit run; the Luhn checksum rejects the overwhelming majority of
/// non-card numbers (IDs, timestamps, serials) that share that shape.
private enum CreditCardMatchSanitizer {
    static func shouldRejectCardValue(_ value: String) -> Bool {
        let digits = value.compactMap { $0.wholeNumberValue }
        guard (13...19).contains(digits.count) else { return true }
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum % 10 != 0
    }
}

/// `iban` matches the country/length shape; the ISO 13616 mod-97 checksum confirms it is a real IBAN.
private enum IBANMatchSanitizer {
    static func shouldRejectIBANValue(_ value: String) -> Bool {
        let normalized = value.uppercased().filter { $0.isLetter || $0.isNumber }
        guard (15...34).contains(normalized.count) else { return true }
        let rearranged = normalized.dropFirst(4) + normalized.prefix(4)
        var remainder = 0
        for character in rearranged {
            guard let scalar = character.unicodeScalars.first else { return true }
            let digits: [Int]
            if character.isNumber {
                digits = [Int(scalar.value - 48)]
            } else {
                // A=10 … Z=35, fed in as two decimal digits.
                let mapped = Int(scalar.value - 55)
                digits = [mapped / 10, mapped % 10]
            }
            for digit in digits {
                remainder = (remainder * 10 + digit) % 97
            }
        }
        return remainder != 1
    }
}

/// `jwt` matches `eyJ…`-shaped triplets; a real JWT has a base64url header decoding to JSON with an `alg`.
private enum JWTMatchSanitizer {
    static func shouldRejectJWTValue(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return true }
        guard let headerData = base64URLDecode(String(segments[0])),
              let object = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              object["alg"] != nil else {
            return true
        }
        return false
    }

    private static func base64URLDecode(_ input: String) -> Data? {
        var base64 = input.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }
        return Data(base64Encoded: base64)
    }
}

/// Doc/sample placeholders (`<your-token>`, `${API_KEY}`, `xxxxxxxx`, `changeme`) match secret shapes but
/// carry no real credential. Kept conservative so real keys (including `sk_test_…`) are never dropped.
private enum PlaceholderSecretSanitizer {
    private static let markerWords = [
        "your", "example", "placeholder", "changeme", "change_me", "redacted",
        "dummy", "insert", "todo", "fixme", "xxxx", "yyyy", "notarealkey",
    ]

    static func isPlaceholder(_ value: String) -> Bool {
        if value.contains("<") || value.contains(">") { return true }
        if value.contains("{{") || value.contains("${") || value.contains("%(") { return true }
        if value.contains("****") || value.contains("....") { return true }
        let lower = value.lowercased()
        if markerWords.contains(where: lower.contains) { return true }
        return false
    }
}

/// Honors inline opt-outs:
///   `… secret …   # offsend:ignore`            suppresses findings on that line
///   `# offsend:ignore-next-line`                suppresses findings on the following line
enum InlineIgnoreFilter {
    private static let token = "offsend:ignore"
    private static let nextLineToken = "offsend:ignore-next-line"

    static func filter(_ entities: [SensitiveEntity], in text: String) -> [SensitiveEntity] {
        guard text.contains(token) else { return entities }
        let lines = text.components(separatedBy: "\n")
        return entities.filter { entity in
            let lineIndex = text[text.startIndex..<entity.range.lowerBound].reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            }
            let line = lineIndex < lines.count ? lines[lineIndex] : ""
            if line.contains(token), !line.contains(nextLineToken) { return false }
            if lineIndex > 0, lines[lineIndex - 1].contains(nextLineToken) { return false }
            return true
        }
    }
}

private enum TextNormalizer {
    /// The full text is always returned and scanned by the deterministic detectors (via windowing).
    /// `wasTruncated` now means only that the input exceeded `maximumLength`, so the optional AI pass
    /// analyzed a prefix rather than the whole text — callers use it for a "partially analyzed" hint.
    static func normalize(_ text: String, maximumLength: Int) -> NormalizedText {
        NormalizedText(text: text, wasTruncated: text.count > maximumLength)
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
        // Provider-specific keys. Each has a distinctive prefix so false positives stay low; all map to
        // `.apiKeyGeneric` (a critical secret) rather than per-provider types to keep the entity model flat.
        // Vercel/Railway core tokens are unprefixed/UUID-shaped, so only Vercel's blob token is fingerprintable
        // here — their generic tokens fall through to `apiKeyGeneric` (`key=value`) or `highEntropyString`.
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bsk-ant-[A-Za-z0-9_-]{20,}\b"#, confidence: 0.99), // Anthropic
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bgsk_[A-Za-z0-9]{20,}\b"#, confidence: 0.98), // Groq
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bxai-[A-Za-z0-9]{20,}\b"#, confidence: 0.98), // xAI
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bAIza[0-9A-Za-z_-]{35}\b"#, confidence: 0.97), // Google / Gemini
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bsbp_[a-f0-9]{40}\b"#, confidence: 0.98), // Supabase personal access token
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bsb_(?:secret|publishable)_[A-Za-z0-9_-]{20,}\b"#, confidence: 0.97), // Supabase API keys
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bre_[A-Za-z0-9]{6,}_[A-Za-z0-9]{16,}\b"#, confidence: 0.95), // Resend
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\blin_(?:api|oauth)_[A-Za-z0-9]{20,}\b"#, confidence: 0.97), // Linear
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bvercel_blob_rw_[A-Za-z0-9]{18,}_[A-Za-z0-9]{18,}\b"#, confidence: 0.97), // Vercel Blob
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bglpat-[A-Za-z0-9_-]{20,}\b"#, confidence: 0.98), // GitLab personal access token
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bhf_[A-Za-z0-9]{30,}\b"#, confidence: 0.96), // Hugging Face
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bSG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}\b"#, confidence: 0.98), // SendGrid
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bnpm_[A-Za-z0-9]{36}\b"#, confidence: 0.97), // npm
        .init(type: .apiKeyGeneric, source: .secret, pattern: #"\bdp\.(?:pt|st|ct|sa|scim|audit)\.[A-Za-z0-9]{40,}\b"#, confidence: 0.97), // Doppler
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
