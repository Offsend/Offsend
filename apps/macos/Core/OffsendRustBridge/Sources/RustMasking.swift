import DetectionCore
import Foundation
import MaskingCore

private struct RustMaskDTO: Decodable {
    let maskedText: String
    let mapping: [String: String]
}

/// `TextMasking` backed by Rust `offsend_mask_text` / `offsend_restore_text`.
/// FFI is required — there is no Swift `MaskingEngine` fallback.
public final class RustMaskingEngine: TextMasking, @unchecked Sendable {
    public init() {}

    public func mask(text: String, entities: [SensitiveEntity], ttl: MappingTTL = .oneHour) -> MaskingResult {
        do {
            let entitiesJSON = try encodeEntities(entities, in: text)
            let json = try text.withCString { cText in
                try entitiesJSON.withCString { cEntities in
                    try RustFFI.call { errOut in
                        offsend_mask_text(cText, cEntities, errOut)
                    }
                }
            }
            let dto = try RustFFI.decode(RustMaskDTO.self, from: json)
            let retention: MaskingResult.Retention = ttl.interval
                .map { .expiring(Date().addingTimeInterval($0)) } ?? .ephemeral
            return MaskingResult(
                maskedText: dto.maskedText,
                mapping: dto.mapping,
                retention: retention
            )
        } catch {
            assertionFailure("Rust mask failed: \(error)")
            // Fail closed for callers that gate on mapping emptiness: no mapping means
            // restore is a no-op; paste flows still use risk/detection separately.
            let retention: MaskingResult.Retention = ttl.interval
                .map { .expiring(Date().addingTimeInterval($0)) } ?? .ephemeral
            return MaskingResult(maskedText: text, mapping: [:], retention: retention)
        }
    }

    public func restore(text: String, mapping: [String: String]) -> String {
        do {
            let mappingData = try JSONEncoder().encode(mapping)
            guard let mappingJSON = String(data: mappingData, encoding: .utf8) else {
                throw RustFFIError.invalidUTF8
            }
            return try text.withCString { cText in
                try mappingJSON.withCString { cMapping in
                    try RustFFI.call { errOut in
                        offsend_restore_text(cText, cMapping, errOut)
                    }
                }
            }
        } catch {
            assertionFailure("Rust restore failed: \(error)")
            return text
        }
    }

    private func encodeEntities(_ entities: [SensitiveEntity], in text: String) throws -> String {
        struct EntityDTO: Encodable {
            let start: Int
            let end: Int
            let value: String
            let type: String
        }
        var items: [EntityDTO] = []
        for entity in entities {
            guard entity.range.lowerBound >= text.startIndex,
                  entity.range.upperBound <= text.endIndex,
                  text[entity.range] == entity.value,
                  let start = utf8Offset(of: entity.range.lowerBound, in: text),
                  let end = utf8Offset(of: entity.range.upperBound, in: text) else {
                continue
            }
            items.append(
                EntityDTO(
                    start: start,
                    end: end,
                    value: entity.value,
                    type: entity.type.rawValue
                )
            )
        }
        let data = try JSONEncoder().encode(items)
        guard let json = String(data: data, encoding: .utf8) else {
            throw RustFFIError.invalidUTF8
        }
        return json
    }

    private func utf8Offset(of index: String.Index, in string: String) -> Int? {
        guard let utf8Index = index.samePosition(in: string.utf8) else { return nil }
        return string.utf8.distance(from: string.utf8.startIndex, to: utf8Index)
    }
}
