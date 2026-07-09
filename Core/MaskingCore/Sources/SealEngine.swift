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
}

public struct SealEngine: TextSealing, Sendable {
    /// Default cap covers typical secrets (JWT, PEM, OpenSSH keys) without unbounded tokens.
    public static let defaultMaxPlaintextBytes = 65_536

    private static let domainSeparation = Data("offsend-seal-v1".utf8)

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

        let nonce = try makeNonce(type: type, plaintext: plainData)
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
        var tokenByValueAndType: [String: String] = [:]
        var replacements: [(range: Range<String.Index>, token: String)] = []
        var coveredUpperBound: String.Index?
        var sealedCount = 0

        for entity in orderedEntities {
            guard entity.range.lowerBound >= text.startIndex,
                  entity.range.upperBound <= text.endIndex,
                  text[entity.range] == entity.value else { continue }

            if let upper = coveredUpperBound, entity.range.lowerBound < upper { continue }

            let type = entity.type.placeholderPrefix
            let cacheKey = "\(type)\0\(entity.value)"
            let token: String
            if let existing = tokenByValueAndType[cacheKey] {
                token = existing
            } else {
                token = try seal(plaintext: entity.value, type: type)
                tokenByValueAndType[cacheKey] = token
            }

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

    private func makeNonce(type: String, plaintext: Data) throws -> AES.GCM.Nonce {
        var message = Self.domainSeparation
        message.append(Data(type.utf8))
        message.append(0)
        message.append(plaintext)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        do {
            return try AES.GCM.Nonce(data: Data(mac.prefix(12)))
        } catch {
            throw SealError.encryptionFailed
        }
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
