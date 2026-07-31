import DetectionCore
import Foundation

private struct RustDetectionDTO: Decodable {
    let scannedText: String
    let wasTruncated: Bool
    let scannedCharacterCount: Int
    let entities: [RustEntityDTO]
}

private struct RustEntityDTO: Decodable {
    let type: String
    let start: Int
    let end: Int
    let value: String
    let confidence: Double
    let source: String?
}

private struct RustDetectOptionsDTO: Encodable {
    let enabledTypes: [String]?
    let maximumLength: Int?
    let honorInlineIgnore: Bool?
    let customDictionaries: [RustCustomDictionaryDTO]?
}

private struct RustCustomDictionaryDTO: Encodable {
    let kind: String
    let value: String
}

/// Bridge to Rust `DetectionEngine` via `offsend_detect_scan`.
public enum RustDetection {
    public static func scan(text: String, options: DetectionOptions = .default) throws -> DetectionResult {
        let optionsJSON = try encodeOptions(options)
        let json = try text.withCString { cText in
            try optionsJSON.withCString { cOptions in
                try RustFFI.call { errOut in
                    offsend_detect_scan(cText, cOptions, errOut)
                }
            }
        }
        let dto = try RustFFI.decode(RustDetectionDTO.self, from: json)
        return try mapDetectionResult(dto)
    }

    private static func encodeOptions(_ options: DetectionOptions) throws -> String {
        let dto = RustDetectOptionsDTO(
            enabledTypes: options.enabledTypes.map(\.rawValue).sorted(),
            maximumLength: options.maximumLength,
            honorInlineIgnore: options.honorInlineIgnore,
            customDictionaries: options.customDictionaries.map {
                RustCustomDictionaryDTO(kind: $0.kind.rawValue, value: $0.value)
            }
        )
        let data = try JSONEncoder().encode(dto)
        guard let json = String(data: data, encoding: .utf8) else {
            throw RustFFIError.invalidUTF8
        }
        return json
    }

    private static func mapDetectionResult(_ dto: RustDetectionDTO) throws -> DetectionResult {
        let scannedText = dto.scannedText
        var entities: [SensitiveEntity] = []
        entities.reserveCapacity(dto.entities.count)

        for item in dto.entities {
            guard let entityType = SensitiveEntityType(rawValue: item.type) else {
                throw RustFFIError.decodingFailed("unknown entity type '\(item.type)'")
            }
            guard let start = utf8Index(at: item.start, in: scannedText),
                  let end = utf8Index(at: item.end, in: scannedText),
                  start <= end else {
                throw RustFFIError.decodingFailed(
                    "invalid UTF-8 range \(item.start)..<\(item.end) for type \(item.type)"
                )
            }
            let source = item.source.flatMap(DetectionSource.init(rawValue:)) ?? .regex
            entities.append(
                SensitiveEntity(
                    type: entityType,
                    range: start..<end,
                    value: item.value,
                    confidence: item.confidence,
                    source: source
                )
            )
        }

        return DetectionResult(
            entities: entities,
            scannedText: scannedText,
            wasTruncated: dto.wasTruncated,
            scannedCharacterCount: dto.scannedCharacterCount
        )
    }

    private static func utf8Index(at offset: Int, in string: String) -> String.Index? {
        guard offset >= 0 else { return nil }
        guard let utf8Index = string.utf8.index(
            string.utf8.startIndex,
            offsetBy: offset,
            limitedBy: string.utf8.endIndex
        ) else {
            return nil
        }
        // UTF-8 byte offset from Rust → String.Index (must land on a Character boundary).
        return String.Index(utf8Index, within: string)
    }
}
