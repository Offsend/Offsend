#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import DetectionCore
import Foundation

public struct SealResult: Equatable, Sendable {
    public let sealedText: String
    public let sealedCount: Int

    public init(sealedText: String, sealedCount: Int) {
        self.sealedText = sealedText
        self.sealedCount = sealedCount
    }
}

/// Parallel to `TextMasking` — lets App / DocumentCore inject sealing without depending on CLI.
public protocol TextSealing: Sendable {
    func seal(text: String, entities: [SensitiveEntity]) throws -> SealResult
    func unseal(text: String) throws -> String
}

/// Detects embed seal tokens without a key (for restore routing in the app).
public enum SealTokenDetector: Sendable {
    public static let pattern: NSRegularExpression = try! NSRegularExpression(
        pattern: #"\{\{([A-Z][A-Z0-9_]*):v1\.([A-Za-z0-9_-]+)\}\}"#
    )

    public static func containsSealTokens(in text: String) -> Bool {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return pattern.firstMatch(in: text, options: [], range: nsRange) != nil
    }

    public static func tokenCount(in text: String) -> Int {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return pattern.numberOfMatches(in: text, options: [], range: nsRange)
    }

    public static func tokenRanges(in text: String) -> [Range<String.Index>] {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return pattern.matches(in: text, options: [], range: nsRange)
            .compactMap { Range($0.range, in: text) }
    }

    /// Drops entropy-only findings fully contained in a seal-token payload.
    /// Token framing alone is not trusted: a live key can be wrapped in a fake
    /// `{{TYPE:v1.…}}` string, so concrete secret detectors must still fire.
    public static func excludingTokenSpans(
        _ entities: [SensitiveEntity],
        in text: String
    ) -> [SensitiveEntity] {
        guard !entities.isEmpty, containsSealTokens(in: text) else { return entities }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let payloadSpans = pattern.matches(in: text, options: [], range: nsRange)
            .compactMap { Range($0.range(at: 2), in: text) }
        return entities.filter { entity in
            guard entity.type == .highEntropyString else { return true }
            return !payloadSpans.contains {
                entity.range.lowerBound >= $0.lowerBound && entity.range.upperBound <= $0.upperBound
            }
        }
    }
}

public struct SealEngine: TextSealing, Sendable {
    /// Default cap covers typical secrets (JWT, PEM, OpenSSH keys) without unbounded tokens.
    public static let defaultMaxPlaintextBytes = 65_536

    private let key: SymmetricKey
    private let maxPlaintextBytes: Int

    public init(key: SymmetricKey, maxPlaintextBytes: Int = SealEngine.defaultMaxPlaintextBytes) {
        self.key = key
        self.maxPlaintextBytes = maxPlaintextBytes
    }

    public init(keyData: Data, maxPlaintextBytes: Int = SealEngine.defaultMaxPlaintextBytes) throws {
        guard keyData.count == 32 else {
            throw SealError.invalidKey("expected 32 bytes, got \(keyData.count)")
        }
        self.key = SymmetricKey(data: keyData)
        self.maxPlaintextBytes = maxPlaintextBytes
    }

    /// Encrypts a single value into a full token `{{TYPE:v1.<base64url>}}`.
    public func seal(plaintext: String, type: String) throws -> String {
        let plainData = Data(plaintext.utf8)
        guard plainData.count <= maxPlaintextBytes else {
            throw SealError.plaintextTooLarge(byteCount: plainData.count, limit: maxPlaintextBytes)
        }

        let nonce = AES.GCM.Nonce()
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(
                plainData,
                using: key,
                nonce: nonce,
                authenticating: Data(type.utf8)
            )
        } catch {
            throw SealError.encryptionFailed
        }

        guard let combined = sealed.combined else {
            throw SealError.encryptionFailed
        }
        return "{{\(type):v1.\(Self.base64URLEncode(combined))}}"
    }

    /// Parses and decrypts a full token string.
    public func open(token: String) throws -> (type: String, plaintext: String) {
        guard token.hasPrefix("{{"), token.hasSuffix("}}") else {
            throw SealError.invalidTokenFormat
        }
        let inner = token.dropFirst(2).dropLast(2)
        guard let colon = inner.firstIndex(of: ":") else {
            throw SealError.invalidTokenFormat
        }
        let type = String(inner[..<colon])
        let versionAndPayload = inner[inner.index(after: colon)...]
        guard versionAndPayload.hasPrefix("v1.") else {
            let version = versionAndPayload.split(separator: ".", maxSplits: 1).first.map(String.init) ?? String(versionAndPayload)
            throw SealError.unsupportedTokenVersion(version)
        }
        let payload = String(versionAndPayload.dropFirst(3))
        return try decrypt(type: type, payload: payload)
    }

    /// Replaces detected entities with sealed tokens. Fails closed if any value exceeds the size limit.
    public func seal(text: String, entities: [SensitiveEntity]) throws -> SealResult {
        let orderedEntities = entities.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var replacements: [(range: Range<String.Index>, token: String)] = []
        var coveredUpperBound: String.Index?
        var sealedCount = 0

        for entity in orderedEntities {
            guard entity.range.lowerBound >= text.startIndex,
                  entity.range.upperBound <= text.endIndex,
                  text[entity.range] == entity.value else { continue }

            if let upper = coveredUpperBound, entity.range.lowerBound < upper { continue }

            let type = entity.type.placeholderPrefix
            let token = try seal(plaintext: entity.value, type: type)

            replacements.append((entity.range, token))
            sealedCount += 1
            coveredUpperBound = Swift.max(coveredUpperBound ?? entity.range.upperBound, entity.range.upperBound)
        }

        var sealedText = text
        for replacement in replacements.reversed() {
            sealedText.replaceSubrange(replacement.range, with: replacement.token)
        }

        return SealResult(sealedText: sealedText, sealedCount: sealedCount)
    }

    /// Decrypts all `{{TYPE:v1.…}}` tokens in `text`. Fails fast on a bad token.
    public func unseal(text: String) throws -> String {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = SealTokenDetector.pattern.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  match.numberOfRanges == 3,
                  let typeRange = Range(match.range(at: 1), in: result),
                  let payloadRange = Range(match.range(at: 2), in: result) else {
                throw SealError.invalidTokenFormat
            }
            let type = String(result[typeRange])
            let payload = String(result[payloadRange])
            let opened = try decrypt(type: type, payload: payload)
            result.replaceSubrange(fullRange, with: opened.plaintext)
        }
        return result
    }

    /// Removes detector findings only when they are fully contained in a token
    /// authenticated by this engine's key. Syntactic lookalikes remain findings.
    public func excludingAuthenticatedTokenSpans(
        _ entities: [SensitiveEntity],
        in text: String
    ) -> [SensitiveEntity] {
        guard !entities.isEmpty else { return entities }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let authenticated = SealTokenDetector.pattern
            .matches(in: text, options: [], range: nsRange)
            .compactMap { match -> Range<String.Index>? in
                guard let range = Range(match.range, in: text),
                      (try? open(token: String(text[range]))) != nil else {
                    return nil
                }
                return range
            }
        return entities.filter { entity in
            !authenticated.contains {
                entity.range.lowerBound >= $0.lowerBound && entity.range.upperBound <= $0.upperBound
            }
        }
    }

    private func decrypt(type: String, payload: String) throws -> (type: String, plaintext: String) {
        guard let combined = Self.base64URLDecode(payload) else {
            throw SealError.invalidTokenFormat
        }
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw SealError.invalidTokenFormat
        }

        let plainData: Data
        do {
            plainData = try AES.GCM.open(box, using: key, authenticating: Data(type.utf8))
        } catch {
            throw SealError.decryptionFailed
        }

        guard let plaintext = String(data: plainData, encoding: .utf8) else {
            throw SealError.decryptionFailed
        }
        return (type, plaintext)
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}
