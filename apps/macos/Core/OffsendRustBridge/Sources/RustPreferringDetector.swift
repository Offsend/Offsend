import DetectionCore
import Foundation
import MaskingCore

/// Deterministic scan via Rust FFI, with an optional on-device AI post-pass.
///
/// AI never replaces the Rust engine: regex/secret hits always come from Rust first,
/// then `AIModelDetecting` may add entities that are merged with `OverlapResolver`.
public final class RustPreferringDetector: SensitiveDataDetecting, @unchecked Sendable {
    private let aiDetector: (any AIModelDetecting)?

    public init(aiDetector: (any AIModelDetecting)? = nil) {
        self.aiDetector = aiDetector
    }

    public func scan(_ request: DetectionRequest) async -> DetectionResult {
        let rustResult: DetectionResult
        do {
            rustResult = try RustDetection.scan(text: request.text, options: request.options)
        } catch {
            assertionFailure("Rust detection failed: \(error)")
            return Self.failClosedResult(for: request.text)
        }

        guard request.options.aiDetectionEnabled else {
            return Self.excludingSealTokenHits(rustResult)
        }

        return await applyAIPostPass(to: rustResult, request: request)
    }

    private static func excludingSealTokenHits(_ result: DetectionResult) -> DetectionResult {
        let filtered = SealTokenDetector.excludingTokenSpans(result.entities, in: result.scannedText)
        guard filtered.count != result.entities.count else { return result }
        return DetectionResult(
            entities: filtered,
            scannedText: result.scannedText,
            wasTruncated: result.wasTruncated,
            scannedCharacterCount: result.scannedCharacterCount,
            aiDetectionError: result.aiDetectionError
        )
    }

    private func applyAIPostPass(
        to rustResult: DetectionResult,
        request: DetectionRequest
    ) async -> DetectionResult {
        let text = rustResult.scannedText
        var aiDetectionError: String?
        var entities = rustResult.entities

        if let aiDetector {
            do {
                let window = request.options.maximumLength
                let aiText = rustResult.wasTruncated ? String(text.prefix(window)) : text
                let aiEntities = try await aiDetector.detect(text: aiText, options: request.options)
                let mapped = rustResult.wasTruncated
                    ? Self.remap(aiEntities, from: aiText, to: text)
                    : aiEntities
                let filteredAI = mapped.filter { request.options.enabledTypes.contains($0.type) }
                entities += filteredAI
            } catch {
                aiDetectionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        } else {
            aiDetectionError = "AI model is not loaded."
        }

        let merged = OverlapResolver.resolve(entities, in: text)
        return RustPreferringDetector.excludingSealTokenHits(DetectionResult(
            entities: merged,
            scannedText: text,
            wasTruncated: rustResult.wasTruncated,
            scannedCharacterCount: rustResult.scannedCharacterCount,
            aiDetectionError: aiDetectionError
        ))
    }

    /// Re-anchors entities found in a prefix substring onto the full scanned text.
    private static func remap(
        _ entities: [SensitiveEntity],
        from source: String,
        to destination: String
    ) -> [SensitiveEntity] {
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

    private static func failClosedResult(for text: String) -> DetectionResult {
        let trimmed = text
        guard !trimmed.isEmpty else {
            return DetectionResult(
                entities: [],
                scannedText: trimmed,
                wasTruncated: false,
                scannedCharacterCount: 0,
                aiDetectionError: "Rust detection failed"
            )
        }
        let entity = SensitiveEntity(
            type: .apiKeyGeneric,
            range: trimmed.startIndex..<trimmed.endIndex,
            value: trimmed,
            confidence: 1.0,
            source: .regex
        )
        return DetectionResult(
            entities: [entity],
            scannedText: trimmed,
            wasTruncated: false,
            scannedCharacterCount: trimmed.count,
            aiDetectionError: "Rust detection failed"
        )
    }
}
