import DetectionCore
import Foundation
import MaskingCore

private struct RustSealResultDTO: Decodable {
    let sealedText: String
    let sealedCount: Int
}

/// Thin bridge to Rust `offsend_seal_*`.
public enum RustSeal {
    /// Default cap covers typical secrets (JWT, PEM, OpenSSH keys) without unbounded tokens.
    public static let defaultMaxPlaintextBytes = 65_536

    public static func seal(
        text: String,
        entities: [SensitiveEntity],
        keyData: Data,
        maxPlaintextBytes: Int = RustSeal.defaultMaxPlaintextBytes
    ) throws -> SealResult {
        guard keyData.count == 32 else {
            throw RustFFIError.nullResult("seal key must be 32 bytes")
        }
        let spans = try encodeSpans(entities, in: text)
        let json = try text.withCString { cText in
            try spans.withCString { cSpans in
                try keyData.withUnsafeBytes { raw -> String in
                    guard let keyPtr = raw.bindMemory(to: UInt8.self).baseAddress else {
                        throw RustFFIError.nullResult("seal key pointer unavailable")
                    }
                    return try RustFFI.call { errOut in
                        offsend_seal_spans(
                            keyPtr,
                            keyData.count,
                            cText,
                            cSpans,
                            maxPlaintextBytes,
                            errOut
                        )
                    }
                }
            }
        }
        let dto = try RustFFI.decode(RustSealResultDTO.self, from: json)
        return SealResult(sealedText: dto.sealedText, sealedCount: dto.sealedCount)
    }

    public static func unseal(text: String, keyData: Data) throws -> String {
        guard keyData.count == 32 else {
            throw RustFFIError.nullResult("seal key must be 32 bytes")
        }
        return try text.withCString { cText in
            try keyData.withUnsafeBytes { raw -> String in
                guard let keyPtr = raw.bindMemory(to: UInt8.self).baseAddress else {
                    throw RustFFIError.nullResult("seal key pointer unavailable")
                }
                return try RustFFI.call { errOut in
                    offsend_unseal_text(keyPtr, keyData.count, cText, errOut)
                }
            }
        }
    }

    private static func encodeSpans(_ entities: [SensitiveEntity], in text: String) throws -> String {
        struct SpanDTO: Encodable {
            let start: Int
            let end: Int
            let value: String
            let typeLabel: String
        }

        var spans: [SpanDTO] = []
        spans.reserveCapacity(entities.count)
        for entity in entities {
            guard entity.range.lowerBound >= text.startIndex,
                  entity.range.upperBound <= text.endIndex,
                  text[entity.range] == entity.value,
                  let start = utf8Offset(of: entity.range.lowerBound, in: text),
                  let end = utf8Offset(of: entity.range.upperBound, in: text) else {
                continue
            }
            spans.append(
                SpanDTO(
                    start: start,
                    end: end,
                    value: entity.value,
                    typeLabel: entity.type.placeholderPrefix
                )
            )
        }

        let data = try JSONEncoder().encode(spans)
        guard let json = String(data: data, encoding: .utf8) else {
            throw RustFFIError.invalidUTF8
        }
        return json
    }

    private static func utf8Offset(of index: String.Index, in string: String) -> Int? {
        guard let utf8Index = index.samePosition(in: string.utf8) else { return nil }
        return string.utf8.distance(from: string.utf8.startIndex, to: utf8Index)
    }
}
